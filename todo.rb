require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "pry"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

before do
  session[:lists] ||= []
end

# GET  /lists      -> view all lists
# GET  /lists/new  -> new list form
# POST /lists      -> create new list
# GET  /lists/1    -> view a single list

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_list_name(name)
  if !(1..100).cover?(name.size)
    "List name must be between 1 and 100 characters."
  elsif session[:lists].any? { |list| list[:name] == name }
    "List name must be unique."
  end
end

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_todo(name)
  if !(1..100).cover?(name.size)
    "Todo name must be between 1 and 100 characters."
  end
end

def load_list(index)
  list = session[:lists].find { |list| list[:id] == index }
  return list if list
  
  session[:error] = "The specified list was not found."
  redirect "/lists"
end

def next_todo_id(list)
  max_id = list[:todos].map { |todo| todo[:id] }.max || 0
  max_id + 1
end

def next_list_id(lists)
  max_id = lists.map { |list| list[:id] }.max || 0
  max_id + 1
end

get "/" do
  redirect "/lists"
end

# View list of lists
get "/lists" do
  @lists = session[:lists]
  erb :lists, layout: :layout
end

# Render the new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

# Create a new list
post "/lists" do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    id = next_list_id(session[:lists])
    session[:lists] << { id: id, name: list_name, todos: [] }
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

# View list
get "/lists/:id" do
  @list_id = params[:id].to_i
  @list = load_list(@list_id)
  
  if @list == nil
    session[:error] = "The specified list was not found."
    redirect "/lists"
  else
    erb :list, layout: :layout
  end
end

# Edit an existing todo list
get "/lists/:id/edit" do
  id = params[:id].to_i
  @list = load_list(id)
  erb :edit_list, layout: :layout
end

# Update an existing todo list
post "/lists/:id" do
  list_name = params[:list_name].strip
  id = params[:id].to_i
  @list = load_list(id)

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @list[:name] = list_name
    session[:success] = "The list has been updated."
    redirect "/lists/#{id}"
  end
end

# Delete a existing todo list
post "/lists/:id/delete" do
  id = params[:id].to_i
  session[:lists].delete_if { |list| list[:id] == id }

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    session[:success] = "The list has been deleted."
    redirect "/lists"
  end
end

# Add new todo item
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)
  text = params[:todo].strip

  error = error_for_todo(text)
  if error
    session[:error] = error
    erb :list, layout: :layout
  else
    id = next_todo_id(@list)
    @list[:todos] << { id: id, name: text, completed: false }
    session[:success] = "The todo was added."
    redirect "/lists/#{@list_id}"
  end
end

# Delete a todo from a list
post "/lists/:list_id/todos/:todo_id/delete" do
  list_id = params[:list_id].to_i
  todo_id = params[:todo_id].to_i
  load_list(list_id)[:todos].delete_if { |todo| todo[:id] == todo_id }

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    session[:success] = "The todo has been deleted."
    redirect "lists/#{list_id}"
  end
end

# Complete all todos on a list
post "/lists/:list_id/complete_all" do
  list_id = params[:list_id].to_i
  todo_list = load_list(list_id)[:todos]
  todo_list.each do |todo|
    todo[:completed] = true
  end

  session[:success] = "The todos has been completed."
  redirect "lists/#{list_id}"
end

# Update status of a todo
post "/lists/:list_id/todos/:todo_id" do
  list_id = params[:list_id].to_i
  todo_id = params[:todo_id].to_i
  todo = load_list(list_id)[:todos].find { |todo| todo[:id] == todo_id }

  todo[:completed] = params[:completed] == 'true'
  session[:success] = "The todo has been updated."
  redirect "lists/#{list_id}"
end

helpers do
  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition do |list|
      list_complete?(list)
    end

    incomplete_lists.each { |list| yield(list, lists.index(list)) }
    complete_lists.each { |list| yield(list, lists.index(list)) }
  end

  def sort_todos(todos, &block)
    incomlete_todos = {}
    complete_todos = {}

    todos.each_with_index do |todo, idx|
      if todo[:completed]
        complete_todos[idx] = todo
      else
        incomlete_todos[idx] = todo
      end
    end

    incomlete_todos.each {|index, todo| yield(todo, index)}
    complete_todos.each {|index, todo| yield(todo, index)}
  end

  def list_complete?(list)
    todos = list[:todos]
    not_completed_todos_count(list) == 0 && todos.size >= 1
  end

  def list_class(list)
    "complete" if list_complete?(list)
  end

  def not_completed_todos_count(list)
    list[:todos].count { |todo| !todo[:completed] }
  end

  def todos_count(list)
    list[:todos].size
  end
end
