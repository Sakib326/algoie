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

    live "/products", ProductLive.Index, :index
    live "/products/new", ProductLive.Index, :new
    live "/products/:id/edit", ProductLive.Index, :edit

    live "/categories", CategoryLive.Index, :index
    live "/categories/new", CategoryLive.Index, :new
    live "/categories/:id/edit", CategoryLive.Index, :edit

    live "/brands", BrandLive.Index, :index
    live "/brands/new", BrandLive.Index, :new
    live "/brands/:id/edit", BrandLive.Index, :edit

    live "/orders", OrderLive.Index, :index
    live "/orders/:id", OrderLive.Show, :show
  end

  # API routes
  scope "/api", AlgoieWeb do
    pipe_through [:api]

    # Add API routes here
  end
end
