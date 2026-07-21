# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :algoie,
  ecto_repos: [Algoie.Repo],
  generators: [timestamp_type: :utc_datetime]

config :algoie, :ai_tools, [
  Algoie.AI.Tools.ListProducts,
  Algoie.AI.Tools.ListOrders,
  Algoie.AI.Tools.CheckInventory,
  Algoie.AI.Tools.QuerySalesReports,
  Algoie.AI.Tools.StoreResources
]

app_url = System.get_env("APP_URL", "http://localhost:4000")
app_uri = URI.parse(app_url)

# APP_URL is the canonical external origin, including scheme and non-default
# port. APP_DOMAIN remains an optional router override for compatibility.
config :algoie, :app_url, app_url
config :algoie, :apex_host, System.get_env("APP_DOMAIN") || app_uri.host || "localhost"
config :algoie, :platform_admin_emails, []
config :algoie, :session_cookie_domain, System.get_env("SESSION_COOKIE_DOMAIN")
config :algoie, :load_email_settings_from_db, true

# Configure the endpoint
config :algoie, AlgoieWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AlgoieWeb.ErrorHTML, json: AlgoieWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Algoie.PubSub,
  live_view: [signing_salt: "cuWIS9Lq"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :algoie, Algoie.Mailer, adapter: Swoosh.Adapters.Local

config :algoie, :email,
  from_name: "Algoie",
  from_address: "noreply@localhost",
  reply_to: nil,
  app_url: app_url

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  algoie: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  algoie: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :algoie, :ash_domains, [
  Algoie.Accounts,
  Algoie.Stores,
  Algoie.Products,
  Algoie.Customers,
  Algoie.Orders,
  Algoie.Media
]

config :algoie,
       :token_signing_secret,
       System.get_env("TOKEN_SIGNING_SECRET", "dev-secret-change-in-prod")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
