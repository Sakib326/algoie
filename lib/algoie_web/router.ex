defmodule AlgoieWeb.Router do
  use AlgoieWeb, :router
  use AshAuthentication.Phoenix.Router

  # The apex host serves the platform (marketing, auth, dashboard).
  # Any subdomain of it (e.g. "nike.<apex>") serves a storefront.
  # Resolved at compile time, so in production :apex_host must be configured
  # (via APP_DOMAIN) at build time. StoreSlugPlug reads the same value.
  @apex_host Application.compile_env(:algoie, :apex_host, "localhost")

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AlgoieWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug AlgoieWeb.Plugs.StoreSlugPlug
    plug AlgoieWeb.Plugs.LoadTenantFromSession
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :store do
    plug AlgoieWeb.Plugs.StoreSlugPlug, require_subdomain: true
  end

  # ═══════════════════════════════════════════════════════════
  # PLATFORM ROUTES (apex host only — e.g. algoie.com / localhost)
  # ═══════════════════════════════════════════════════════════

  scope "/", AlgoieWeb, host: @apex_host do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/register", RegistrationLive, :index
    live "/sign-in", LoginLive, :index

    get "/switch-store/:store_id", StoreSwitchController, :switch

    sign_out_route(AuthController, "/sign-out")
    auth_routes(AuthController, Algoie.Accounts.User, path: "/auth")

    reset_route(
      auth_routes_prefix: "/auth",
      overrides: [AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # ═══════════════════════════════════════════════════════════
  # DASHBOARD ROUTES (apex host, /dashboard — auth required)
  # ═══════════════════════════════════════════════════════════

  scope "/", AlgoieWeb, host: @apex_host do
    pipe_through [:browser]

    ash_authentication_live_session :dashboard,
      otp_app: :algoie,
      on_mount: [{AlgoieWeb.Live.OnDashboardMount, :default}] do
      live "/dashboard", DashboardLive, :index
      live "/dashboard/products", ProductLive.Index, :index
      live "/dashboard/products/new", ProductLive.Wizard, :new
      live "/dashboard/products/wizard", ProductLive.Wizard, :new
      live "/dashboard/products/:id/edit", ProductLive.Wizard, :edit
      live "/dashboard/categories", CategoryLive.Index, :index
      live "/dashboard/categories/new", CategoryLive.Index, :new
      live "/dashboard/categories/:id/edit", CategoryLive.Index, :edit
      live "/dashboard/brands", BrandLive.Index, :index
      live "/dashboard/brands/new", BrandLive.Index, :new
      live "/dashboard/brands/:id/edit", BrandLive.Index, :edit
      live "/dashboard/media", MediaLive.Index, :index
      live "/dashboard/orders", OrderLive.Index, :index
      live "/dashboard/orders/:id", OrderLive.Show, :show
      live "/dashboard/conversations", ConversationLive.Index, :index
      live "/dashboard/campaigns", CampaignLive.Index, :index
      live "/store-select", StoreSelectorLive, :index
    end
  end

  # ═══════════════════════════════════════════════════════════
  # STOREFRONT ROUTES (store1.<apex> — any subdomain)
  # These match on any host; the :store pipeline (require_subdomain)
  # returns 404 if reached without a store subdomain.
  # ═══════════════════════════════════════════════════════════

  scope "/", AlgoieWeb do
    pipe_through [:browser, :store]

    live "/", StorefrontHomeLive, :index
    live "/store", StorefrontHomeLive, :index
    live "/products", StorefrontProductLive.Index, :index
    live "/products/:slug", StorefrontProductLive.Show, :show
  end

  # ═══════════════════════════════════════════════════════════
  # API ROUTES
  # ═══════════════════════════════════════════════════════════

  scope "/api", AlgoieWeb do
    pipe_through [:api]
  end
end
