import Config

config :algoie, ecto_repos: [Algoie.Repo]

if config_env() == :test do
  config :algoie, Algoie.Repo,
    username: System.get_env("DATABASE_USERNAME", "postgres"),
    password: System.get_env("DATABASE_PASSWORD", "postgres"),
    hostname: System.get_env("DATABASE_HOST", "localhost"),
    database:
      System.get_env("DATABASE_NAME", "algoie_test#{System.get_env("MIX_TEST_PARTITION")}"),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :algoie, Algoie.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
end

config :algoie, :ash_domains, [
  Algoie.Accounts,
  Algoie.Stores
]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :algoie, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :algoie, AlgoieWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
