require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

##### ROUTE HELPERS #####

VALID_EXTENSIONS = %w[.md .txt].freeze

##### password protection helpers #####

def encrypt_password(password)
  BCrypt::Password.create(password)
end

def correct_password?(password, db_password)
  BCrypt::Password.new(db_password) == password
end

##### path helpers #####

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def credentials_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users/users.yml', __FILE__)
  end
end

def history_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/history.yml', __FILE__)
  else
    File.expand_path('../data/history/history.yml', __FILE__)
  end
end

##### validity helpers #####

def valid_user_credentials?(name, password)
  credentials = load_user_credentials
  credentials.key?(name) && correct_password?(password, credentials[name])
end

def invalid_filename?(filename)
  File.extname(filename).empty? ||
    File.basename(filename, '.*').empty? ||
    File.basename(filename, '.*') =~ /[^A-Za-z0-9_-]/
end

def unapproved_document_type?(filename)
  !VALID_EXTENSIONS.include?(File.extname(filename))
end

def signed_in?
  session.key?(:username)
end

##### user credential helpers #####

def load_user_credentials
  YAML.load_file(credentials_path) || {}
end

def add_user_credentials(username, password)
  user_credentials = load_user_credentials
  return if user_credentials[username] || username.empty? || password.empty?

  user_credentials[username] = encrypt_password(password)

  File.open(credentials_path, 'w') do |f|
    YAML.dump(user_credentials, f)
  end
end

##### version history helpers #####

def load_history
  YAML.load_file(history_path) || {}
end

def store_version_history(filename, content)
  history = load_history
  (history[filename] ||= []) << content

  File.open(history_path, 'w') do |f|
    YAML.dump(history, f)
  end
end

##### file helpers #####

def render_if_markdown(path, file_name)
  return unless File.extname(file_name) == '.md'
  Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(File.read(path))
end

def render_correct_filetype(path, filename)
  markdown = render_if_markdown(path, filename)
  markdown ? erb(markdown) : send_file(path)
end

def create_document(name, content = '')
  File.open(File.join(data_path, name), 'w') do |file|
    file.write(content)
  end
end

##### message helpers #####

def error_message_if_invalid_file(filename)
  if invalid_filename?(filename)
    session[:message] = 'Invalid input! Please enter a valid filename.'
  elsif unapproved_document_type?(filename)
    session[:message] = 'The file extensions we currently accept are:'\
                        " #{VALID_EXTENSIONS.join(', ')}"
  elsif File.file?(File.join(data_path, filename))
    session[:message] = "#{filename} already exists! Try a new name."
  end
end

def redirect_to_index_if_not_signed_in
  return if signed_in?

  session[:message] = 'You must be signed in to do that.'
  redirect '/'
end

##### VIEW HELPERS #####

helpers do
  def version_history_exists?(filename)
    load_history.key?(filename)
  end
end

##### ROUTES #####

get '/' do
  pattern = File.join(data_path, '*.*')
  files = Dir.glob(pattern).map { |path| File.basename(path) }
  @images, @documents = files.partition { |f| unapproved_document_type?(f) }

  erb :index, layout: :layout
end

##### user signin #####

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

##### user signout #####

post '/users/signout' do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect '/'
end

##### user signup #####

get '/users/signup' do
  erb :signup, layout: :layout
end

post '/users/signup' do
  username = params[:username].strip
  password = params[:password]
  new_user = add_user_credentials(username, password)

  if new_user
    session[:message] = "Welcome #{username}, our newest member!"
    session[:username] = username
    redirect '/'
  else
    session[:message] = "Unavailable username or password! Please try again."
    status 422
    erb :signup, layout: :layout
  end
end

##### upload image #####

get '/upload' do
  redirect_to_index_if_not_signed_in

  erb :upload, layout: :layout
end

post '/upload' do
  redirect_to_index_if_not_signed_in

  name = params[:image][:filename]
  image = params[:image][:tempfile]

  File.open(File.join(data_path, name), 'wb') do |file|
    file.write(image.read)
  end

  session[:message] = "An image: #{name}, has been added."
  redirect '/'
end

##### add new document #####

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

##### render selected document #####

get '/:file_name' do
  path = File.join(data_path, File.basename(params[:file_name]))

  if File.file?(path)
    render_correct_filetype(path, params[:file_name])
  else
    session[:message] = "#{params[:file_name]} does not exist."
    redirect '/'
  end
end

##### edit document #####

get '/:file_name/edit' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  @file_body = File.read(path)

  erb :edit, layout: :layout
end

post '/:file_name/edit' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  store_version_history(params[:file_name], File.read(path))

  File.write(path, params[:contents])

  session[:message] = "#{params[:file_name]} has been updated."
  redirect '/'
end

##### alter file by deletion or duplication #####

# delete file or redirect for duplication
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

# perform duplication
post '/:file_name/duplicate' do
  redirect_to_index_if_not_signed_in

  @ext_name = File.extname(params[:file_name])
  duplicate_filename = "#{params[:duplicate_document]}#{@ext_name}"

  error = error_message_if_invalid_file(duplicate_filename)
  if error
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

##### version history #####

get '/:file_name/history' do
  redirect_to_index_if_not_signed_in

  @versions = load_history[params[:file_name]]

  erb :history, layout: :layout
end
