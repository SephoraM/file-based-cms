require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'

configure do
  enable :sessions
  set :session_secret, 'secret'
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

def admin?(username, password)
  username == 'admin' && password == 'secret'
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

# submit username and password
post '/users/signin' do
  if admin?(params[:username], params[:password])
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
  path = File.join(data_path, params[:file_name])
  @file_body = File.read(path)

  erb :edit, layout: :layout
end

# submit the 'saved changes'
post '/:file_name/edit' do
  path = File.join(data_path, params[:file_name])
  File.write(path, params[:contents])

  session[:message] = "#{params[:file_name]} has been updated."
  redirect '/'
end

# create the new document
post '/new' do
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
  path = File.join(data_path, params[:file_name])
  File.delete(path)

  session[:message] = "#{params[:file_name]} has been deleted."
  redirect '/'
end
