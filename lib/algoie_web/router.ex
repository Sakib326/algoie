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
    plug AlgoieWeb.Plugs.LoadStorefrontCustomer
  end

  # ═══════════════════════════════════════════════════════════
  # PLATFORM ROUTES (apex host only — e.g. algoie.com / localhost)
  # ═══════════════════════════════════════════════════════════

  scope "/", AlgoieWeb, host: @apex_host do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/register", RegistrationLive, :index
    live "/sign-in", LoginLive, :index
    live "/forgot-password", ForgotPasswordLive, :index

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
      live "/dashboard/inventory", InventoryLive.Index, :index
      live "/dashboard/orders", OrderLive.Index, :index
      live "/dashboard/orders/new", OrderLive.New, :new
      live "/dashboard/orders/:id/invoice", OrderLive.Invoice, :show
      live "/dashboard/orders/:id", OrderLive.Show, :show
      live "/dashboard/coupons", CouponLive.Index, :index
      live "/dashboard/delivery-charges", DeliveryChargeLive.Index, :index
      live "/dashboard/customers", CustomerLive.Index, :index
      live "/dashboard/customers/new", CustomerLive.New, :new
      live "/dashboard/customers/:id", CustomerLive.Show, :show
      live "/dashboard/conversations", ConversationLive.Index, :index
      live "/dashboard/campaigns", CampaignLive.Index, :index
      live "/dashboard/settings", StoreSettingsLive, :edit
      live "/dashboard/team", TeamLive.Index, :index
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
    get "/cart", StorefrontCartController, :show
    post "/cart/items", StorefrontCartController, :add
    post "/cart/update", StorefrontCartController, :update
    delete "/cart/items/:variant_id", StorefrontCartController, :remove
    get "/checkout", StorefrontCheckoutController, :new
    post "/checkout", StorefrontCheckoutController, :create
    get "/order-confirmation/:id", StorefrontCheckoutController, :confirmation
    get "/account/register", StorefrontCustomerController, :register
    post "/account/register", StorefrontCustomerController, :create_account
    get "/account/sign-in", StorefrontCustomerController, :sign_in
    post "/account/sign-in", StorefrontCustomerController, :authenticate
    get "/account/forgot-password", StorefrontCustomerController, :forgot_password
    post "/account/forgot-password", StorefrontCustomerController, :request_password_reset
    post "/account/reset-password", StorefrontCustomerController, :reset_password
    delete "/account/sign-out", StorefrontCustomerController, :sign_out
    get "/account", StorefrontCustomerController, :show
    post "/account/profile", StorefrontCustomerController, :update_profile
    post "/account/addresses", StorefrontCustomerController, :create_address
    get "/account/orders/:id", StorefrontCustomerController, :order
  end

  # ═══════════════════════════════════════════════════════════
  # API ROUTES
  # ═══════════════════════════════════════════════════════════

  scope "/api", AlgoieWeb do
    pipe_through [:api]
  end
end
