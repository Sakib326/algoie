import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :algoie, Algoie.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "algoie_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :algoie, AlgoieWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "kxaKgM7o2MneHJ+oA9MgA/DzS1UguHYwl9EF9SBL709UPCH5inx/DlTwIS9gwaN4",
  server: false

# In test we don't send emails
config :algoie, Algoie.Mailer, adapter: Swoosh.Adapters.Test

# Phoenix's test connection uses "www.example.com" as the host, so treat that as
# the apex host in tests to exercise the platform routes.
config :algoie, :apex_host, "www.example.com"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
