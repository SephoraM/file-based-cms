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
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def test_index
    create_document "about.txt"
    create_document "changes.txt"
    create_document "history.txt"

    # signing in before testing the index page
    post "/users/signin", username: "admin", password: "secret"

    get "/"
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
    # signing in order to test the index page
    post "/users/signin", username: "admin", password: "secret"

    get "/hello.txt"
    assert_equal 302, last_response.status

    get last_response.location
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body,  "hello.txt does not exist"
  end

  def test_editing_document
    create_document "changes.txt"

    get "/changes.txt/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_updating_document
    # signing in order to test the index page
    post "/users/signin", username: "admin", password: "secret"

    post "/changes.txt/edit", contents: "new content"

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_includes last_response.body, "changes.txt has been updated"

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_new_document_view
    get '/new'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<button type"
  end

  def test_invalid_filename_input
    post '/new', new_document: "   "

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_filename_created
    # signing in order to test the index page
    post "/users/signin", username: "admin", password: "secret"

    post '/new', new_document: "test.txt"
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test.txt has been created."
    assert_includes last_response.body, "test.txt</a>"
  end

  def test_deleting_document
    # signing in order to test the index page
    post "/users/signin", username: "admin", password: "secret"

    create_document "test.txt"

    post "/test.txt/delete"

    assert_equal 302, last_response.status

    get last_response["location"]
    assert_includes last_response.body, "test.txt has been deleted."

    get "/"
    refute_includes last_response.body, "test.txt"
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

    get last_response["location"]
    assert_includes last_response.body, "Welcome!"
    assert_includes last_response.body, 'Signed in as admin'
  end

  def test_signout
    post '/users/signout'

    assert_equal 302, last_response.status

    get last_response["location"]
    assert_equal 200, last_response.status

    assert_includes last_response.body, "You have been signed out"
    assert_includes last_response.body, "Sign In"
  end
end
