import Config

app_url =
  System.get_env("APP_URL", Application.get_env(:algoie, :app_url, "http://localhost:4000"))

app_uri = URI.parse(app_url)

if app_uri.scheme not in ["http", "https"] or is_nil(app_uri.host) or
     app_uri.path not in [nil, "", "/"] or not is_nil(app_uri.query) or
     not is_nil(app_uri.fragment) do
  raise "APP_URL must be an http:// or https:// origin without a path, query, or fragment, got: #{inspect(app_url)}"
end

config :algoie, :app_url, String.trim_trailing(app_url, "/")
config :algoie, :apex_host, System.get_env("APP_DOMAIN") || app_uri.host

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
  Algoie.Stores,
  Algoie.Products,
  Algoie.Customers,
  Algoie.Orders,
  Algoie.Media
]

platform_admin_emails =
  System.get_env("PLATFORM_ADMIN_EMAILS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

platform_admin_emails =
  if config_env() == :dev do
    Enum.uniq(["saas-owner@algoie.local" | platform_admin_emails])
  else
    platform_admin_emails
  end

config :algoie,
       :platform_admin_emails,
       platform_admin_emails

if config_env() == :prod do
  token_signing_secret =
    System.get_env("TOKEN_SIGNING_SECRET") ||
      raise """
      environment variable TOKEN_SIGNING_SECRET is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :algoie, :token_signing_secret, token_signing_secret

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = app_uri.host
  scheme = app_uri.scheme
  port = app_uri.port || if(scheme == "https", do: 443, else: 80)

  config :algoie, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :algoie, AlgoieWeb.Endpoint,
    url: [host: host, port: port, scheme: scheme],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  email_provider = System.get_env("EMAIL_PROVIDER", "resend")

  mailer_config =
    case email_provider do
      "resend" ->
        api_key =
          System.get_env("RESEND_API_KEY") ||
            raise "RESEND_API_KEY is required when EMAIL_PROVIDER=resend"

        [adapter: Swoosh.Adapters.Resend, api_key: api_key]

      "local" ->
        [adapter: Swoosh.Adapters.Local]

      unsupported ->
        raise "Unsupported EMAIL_PROVIDER=#{inspect(unsupported)}. Supported values: resend, local"
    end

  config :algoie, Algoie.Mailer, mailer_config

  config :algoie, :email,
    from_name: System.get_env("EMAIL_FROM_NAME", "Algoie"),
    from_address: System.get_env("EMAIL_FROM_ADDRESS", "noreply@#{host}"),
    reply_to: System.get_env("EMAIL_REPLY_TO"),
    app_url: String.trim_trailing(app_url, "/")
end
