defmodule AlgoieWeb.PageController do
  use AlgoieWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
