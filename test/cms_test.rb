ENV["RACK_ENV"] = "test"

require 'fileutils'

require "minitest/autorun"
require "rack/test"


require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    add_user_credentials('admin', encrypt_password('secret'))
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_credentials
    {"rack.session" => { username: "admin", password: "secret"} }
  end

  def test_index
    create_document "about.txt"
    create_document "changes.txt"
    create_document "history.txt"

    get "/", {}, admin_credentials
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body,  "changes.txt"
    assert_includes last_response.body,  "about.txt"
    assert_includes last_response.body,  "history.txt"
  end

  def test_about
    create_document "about.txt", "Whereupon the slave was pardoned and"

    get "/about.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body,  "Whereupon the slave was pardoned and"
  end

  def test_history
    create_document "history.txt", "Yukihiro Matsumoto dreams up Ruby."

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body,  "Yukihiro Matsumoto dreams up Ruby."
  end

  def test_markdown
    create_document "markdown-example.md", "# An h1 header"

    get "/markdown-example.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body,  "<h1>An h1 header</h1>"
  end

  def test_incorrect_input
    get "/hello.txt"

    assert_equal 302, last_response.status
    assert_equal "hello.txt does not exist.", session[:message]
  end

  def test_editing_document_signed_in
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_credentials

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_document_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    get last_response['location']
    assert_nil session[:username]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_updating_document_signed_in
    get '/', {}, admin_credentials

    post "/changes.txt/edit", contents: "new content"

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_updating_document_signed_out
    post "/changes.txt/edit", contents: "new content"

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    get last_response['location']
    assert_nil session[:username]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_new_document_view_signed_in
    get '/new', {}, admin_credentials

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<button type"
  end

  def test_new_document_view_signed_out
    get '/new'

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    get last_response['location']
    assert_nil session[:username]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_invalid_filename_input
    get '/', {}, admin_credentials

    post '/new', new_document: "   "

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_filename_created_signed_in
    get '/', {}, admin_credentials

    post '/new', new_document: "test.txt"
    assert_equal 302, last_response.status
    assert_equal "test.txt has been created.", session[:message]

    get "/"
    assert_includes last_response.body, "test.txt"
  end

  def test_filename_created_signed_out
    get '/'

    post '/new', new_document: "test.txt"
    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    get last_response['location']
    assert_nil session[:username]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_deleting_document_signed_in
    create_document "test.txt"

    post "/test.txt/delete", {}, admin_credentials

    assert_equal 302, last_response.status
    assert_equal "test.txt has been deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end

  def test_deleting_document_signed_out
    create_document "test.txt"

    post "/test.txt/delete"

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]

    get last_response['location']
    assert_nil session[:username]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end

  def test_signin_page
    get '/users/signin'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username: </label>"
    assert_includes last_response.body, "Sign in</button>"
  end

  def test_invalid_signin_credentials
    post '/users/signin', username: 'bob', password: 'foo'

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_signin_as_admin
    post "/users/signin", username: "admin", password: "secret"

    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["location"]
    assert_includes last_response.body, 'Signed in as admin'
  end

  def test_signout
    get "/", {}, admin_credentials
    assert_includes last_response.body, "Signed in as admin"

    post '/users/signout'

    assert_equal 302, last_response.status
    assert_equal "You have been signed out.", session[:message]

    get last_response["location"]
    assert_nil session[:username]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"
  end
end
