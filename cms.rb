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

def error_message_if_invalid(filename)
  if filename.strip.empty?
    session[:message] = 'A name is required.'
  elsif File.extname(filename).empty?
    session[:message] = 'A file extension is required.'
  end
end

def signed_in?
  session.key?(:username)
end

def redirect_to_index_if_not_signed_in
  unless signed_in?
    session[:message] = 'You must be signed in to do that.'
    redirect '/'
  end
end

before do
  add_user_credentials('developer', encrypt_password('letmein'))
end

get '/' do
  pattern = File.join(data_path, "*")
  @documents = Dir.glob(pattern).map { |path| File.basename(path) }

  erb :index, layout: :layout
end

# render for sign in
get '/users/signin' do
  erb :signin
end

# submit username and passwords
post '/users/signin' do
  username = params[:username]

  if valid_user_credentials?(username, params[:password])
    session[:message] = "Welcome!"
    session[:username] = params[:username]
    redirect '/'
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin
  end
end

# Sign out
post '/users/signout' do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect '/'
end

# render for the creation of documents
get '/new' do
  redirect_to_index_if_not_signed_in

  erb :new, layout: :layout
end

# render data files
get '/:file_name' do
  path = File.join(data_path, params[:file_name])

  if File.exist?(path)
    markdown = render_if_markdown(path, params[:file_name])
    markdown ? erb(markdown) : send_file(path)
  else
    session[:message] = "#{params[:file_name]} does not exist."
    redirect '/'
  end
end

# render for any file that is selected
get '/:file_name/edit' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  @file_body = File.read(path)

  erb :edit, layout: :layout
end

# submit the 'saved changes'
post '/:file_name/edit' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  File.write(path, params[:contents])

  session[:message] = "#{params[:file_name]} has been updated."
  redirect '/'
end

# create the new document
post '/new' do
  redirect_to_index_if_not_signed_in

  error = error_message_if_invalid(params[:new_document])
  if error
    status 422
    erb :new, layout: :layout
  else
    create_document(params[:new_document])
    session[:message] = "#{params[:new_document]} has been created."
    redirect '/'
  end
end

# delete a specified file
post '/:file_name/delete' do
  redirect_to_index_if_not_signed_in

  path = File.join(data_path, params[:file_name])
  File.delete(path)

  session[:message] = "#{params[:file_name]} has been deleted."
  redirect '/'
end
