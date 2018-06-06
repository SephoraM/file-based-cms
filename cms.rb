require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

VALID_EXTENSIONS = %w[.md .txt].freeze
VALID_IMAGE_EXTENSIONS = %w[.jpg .png].freeze

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def encrypt_password(password)
  BCrypt::Password.create(password)
end

def correct_password?(password, db_password)
  BCrypt::Password.new(db_password) == password
end

def render_if_markdown(path, file_name)
  return unless File.extname(file_name) == '.md'
  Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(File.read(path))
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def image_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data/images', __FILE__)
  else
    File.expand_path('../data/images', __FILE__)
  end
end

def credentials_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def add_user_credentials(username, password)
  user_credentials = load_user_credentials || {}
  return if user_credentials[username]

  user_credentials[username] = password

  File.open(credentials_path, 'w') do |f|
    YAML.dump(user_credentials, f)
  end
end

def valid_user_credentials?(name, password)
  credentials = load_user_credentials
  credentials.key?(name) && correct_password?(password, credentials[name])
end

def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

def invalid_filename?(filename)
  File.extname(filename).empty? || File.basename(filename, '.*').empty?
end

def unapproved_image_type?(filename)
  !VALID_IMAGE_EXTENSIONS.include?(File.extname(filename))
end

def unapproved_document_type?(filename)
  !VALID_FILE_EXTENSIONS.include?(File.extname(filename))
end

def error_message_if_invalid_file(filename)
  if invalid_filename?(filename)
    session[:message] = 'Invalid input! Please enter the complete filename.'
  elsif unapproved_document_type?(filename)
    session[:message] = 'The file extensions we currently accept are:'\
                        " #{VALID_FILE_EXTENSIONS.join(', ')}"
  end
end

def error_message_if_invalid_image(image)
  if invalid_filename?(image)
    session[:message] = 'Invalid input! Please enter the complete image name.'
  elsif unapproved_image_type?(image)
    session[:message] = 'The image file extensions we currently accept are:'\
                        " #{VALID_IMAGE_EXTENSIONS.join(', ')}"
  end
end

def signed_in?
  session.key?(:username)
end

def redirect_to_index_if_not_signed_in
  return if signed_in?

  session[:message] = 'You must be signed in to do that.'
  redirect '/'
end

get '/' do
  pattern = File.join(data_path, "*")
  @documents = Dir.glob(pattern).map { |path| File.basename(path) }

  erb :index, layout: :layout
end

get '/users/signin' do
  erb :signin, layout: :layout
end

post '/users/signin' do
  username = params[:username]

  if valid_user_credentials?(username, params[:password])
    session[:message] = "Welcome!"
    session[:username] = params[:username]
    redirect '/'
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin, layout: :layout
  end
end

post '/users/signout' do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect '/'
end

get '/users/signup' do
  erb :signup, layout: :layout
end

post '/users/signup' do
  username = params[:username]
  new_user = add_user_credentials(username, encrypt_password(params[:password]))

  if new_user
    session[:message] = "Hello, #{username}! A big welcome to our newest member"
    session[:username] = params[:username]
    redirect '/'
  else
    session[:message] = "That username already exists. Pick a new name please."
    status 422
    erb :signup, layout: :layout
  end
end

get '/upload' do
  redirect_to_index_if_not_signed_in

  erb :upload, layout: :layout
end

post '/upload' do
  redirect_to_index_if_not_signed_in

  error = error_message_if_invalid_image(params[:image])
  if error
    status 422
    erb :upload, layout: :layout
  else
    create_document(params[:new_document])
    session[:message] = "#{params[:new_document]} has been created."
    redirect '/'
  end
end

get '/new' do
  redirect_to_index_if_not_signed_in

  erb :new, layout: :layout
end

post '/new' do
  redirect_to_index_if_not_signed_in

  error = error_message_if_invalid_file(params[:new_document])
  if error
    status 422
    erb :new, layout: :layout
  else
    create_document(params[:new_document])
    session[:message] = "#{params[:new_document]} has been created."
    redirect '/'
  end
end

get '/:file_name' do
  path = File.join(data_path, params[:file_name])

  if File.file?(path)
    markdown = render_if_markdown(path, params[:file_name])
    markdown ? erb(markdown) : send_file(path)
  else
    session[:message] = "#{params[:file_name]} does not exist."
    redirect '/'
  end
end

get '/:file_name/edit' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  @file_body = File.read(path)

  erb :edit, layout: :layout
end

post '/:file_name/edit' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  File.write(path, params[:contents])

  session[:message] = "#{params[:file_name]} has been updated."
  redirect '/'
end

post '/:file_name/alter' do
  redirect_to_index_if_not_signed_in

  if params[:delete]
    path = File.join(data_path, params[:file_name])
    File.delete(path)

    session[:message] = "#{params[:file_name]} has been deleted."
    redirect '/'
  elsif params[:duplicate]
    redirect "/#{params[:file_name]}/duplicate"
  end
end

get '/:file_name/duplicate' do
  @base_name = File.basename(params[:file_name], '.*')
  @ext_name = File.extname(params[:file_name])

  erb :duplicate, layout: :layout
end

post '/:file_name/duplicate' do
  redirect_to_index_if_not_signed_in

  @ext_name = File.extname(params[:file_name])
  duplicate_filename = "#{params[:duplicate_document]}#{@ext_name}"

  if File.file?(File.join(data_path, duplicate_filename))
    session[:message] = "#{duplicate_filename} already exists! Try a new name."

    @base_name = File.basename(params[:file_name], '.*')

    erb :duplicate, layout: :layout
  else
    path = File.join(data_path, params[:file_name])
    content = File.read(path)
    create_document(duplicate_filename, content)

    session[:message] = "A duplicate copy of #{params[:file_name]} has been "\
                        "created. The new document is #{duplicate_filename}."
    redirect '/'
  end
end
