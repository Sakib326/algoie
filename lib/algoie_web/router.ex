defmodule AlgoieWeb.Router do
  use AlgoieWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AlgoieWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :store do
    plug AlgoieWeb.Plugs.StoreSlugPlug
  end

  scope "/", AlgoieWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Store-scoped routes
  scope "/", AlgoieWeb do
    pipe_through [:browser, :store]

    # Add store-specific routes here
  end

  # API routes
  scope "/api", AlgoieWeb do
    pipe_through [:api]

    # Add API routes here
  end
end
