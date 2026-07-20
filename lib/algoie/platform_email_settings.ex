defmodule Algoie.PlatformEmailSettings do
  @moduledoc "Database-backed platform mail configuration with encrypted provider credentials."

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "platform_email_settings" do
    field :provider, :string, default: "local"
    field :enabled, :boolean, default: true
    field :api_key_ciphertext, :string
    field :api_key, :string, virtual: true, redact: true
    field :smtp_host, :string
    field :smtp_port, :integer, default: 587
    field :smtp_username, :string
    field :smtp_password_ciphertext, :string
    field :smtp_password_hint, :string
    field :smtp_password, :string, virtual: true, redact: true
    field :smtp_auth, :string, default: "if_available"
    field :smtp_tls, :string, default: "if_available"
    field :from_name, :string, default: "Algoie"
    field :from_address, :string, default: "noreply@localhost"
    field :reply_to, :string
    field :app_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def get do
    case Repo.one(from settings in __MODULE__, order_by: [asc: settings.inserted_at], limit: 1) do
      nil -> default_settings()
      settings -> %{settings | app_url: AlgoieWeb.PublicURL.origin()}
    end
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :provider,
      :enabled,
      :api_key,
      :smtp_host,
      :smtp_port,
      :smtp_username,
      :smtp_password,
      :smtp_auth,
      :smtp_tls,
      :from_name,
      :from_address,
      :reply_to,
      :app_url
    ])
    |> validate_required([:provider, :from_name, :from_address, :app_url])
    |> validate_inclusion(:provider, ["local", "smtp", "resend"])
    |> validate_number(:smtp_port, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_inclusion(:smtp_auth, ["always", "if_available", "never"])
    |> validate_inclusion(:smtp_tls, ["always", "if_available", "never"])
    |> validate_format(:from_address, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_format(:reply_to, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_format(:app_url, ~r/^https?:\/\//, message: "must start with http:// or https://")
    |> require_resend_key()
    |> require_smtp_credentials()
    |> encrypt_changed_credentials()
  end

  def save(attrs) do
    settings = get()

    attrs =
      if Map.has_key?(attrs, :app_url),
        do: Map.put(attrs, :app_url, AlgoieWeb.PublicURL.origin()),
        else: Map.put(attrs, "app_url", AlgoieWeb.PublicURL.origin())

    changeset = changeset(settings, attrs)

    result =
      if settings.id do
        Repo.update(changeset)
      else
        Repo.insert(changeset)
      end

    with {:ok, saved} <- result do
      apply_runtime(saved)
      {:ok, saved}
    end
  end

  def reset_credentials do
    case get() do
      %__MODULE__{id: nil} = settings ->
        {:ok, settings}

      settings ->
        settings
        |> change(api_key_ciphertext: nil, smtp_password_ciphertext: nil, smtp_password_hint: nil)
        |> Repo.update()
    end
  end

  def apply_runtime(settings \\ get()) do
    config = delivery_config(settings)
    mailer_config = config.mailer

    Application.put_env(:algoie, Algoie.Mailer, mailer_config)

    Application.put_env(:algoie, :email,
      from_name: settings.from_name,
      from_address: settings.from_address,
      reply_to: blank_to_nil(settings.reply_to),
      app_url: settings.app_url,
      enabled: settings.enabled
    )

    :ok
  end

  def delivery_config(settings \\ get()) do
    mailer_config =
      case settings.provider do
        "resend" ->
          [adapter: Swoosh.Adapters.Resend, api_key: decrypt_key(settings.api_key_ciphertext)]

        "smtp" ->
          [
            adapter: Swoosh.Adapters.SMTP,
            relay: settings.smtp_host,
            port: settings.smtp_port,
            username: settings.smtp_username,
            password: decrypt_key(settings.smtp_password_ciphertext),
            auth: smtp_mode(settings.smtp_auth),
            tls: smtp_mode(settings.smtp_tls),
            tls_options: Algoie.EmailRuntime.smtp_tls_options(settings.smtp_host),
            ssl: false
          ]

        _ ->
          [adapter: Swoosh.Adapters.Local]
      end

    %{
      enabled: settings.enabled,
      source: :platform,
      mailer: mailer_config,
      email: [
        from_name: settings.from_name,
        from_address: settings.from_address,
        reply_to: blank_to_nil(settings.reply_to),
        app_url: settings.app_url
      ]
    }
  end

  def configured_key?(%__MODULE__{api_key_ciphertext: value}), do: value not in [nil, ""]

  def configured_password?(%__MODULE__{smtp_password_ciphertext: value}),
    do: value not in [nil, ""]

  def masked_password(%__MODULE__{smtp_password_hint: hint}) when hint not in [nil, ""],
    do: "••••#{hint}"

  def masked_password(_settings), do: "Not configured"

  defp default_settings do
    email = Application.get_env(:algoie, :email, [])
    mailer = Application.get_env(:algoie, Algoie.Mailer, [])
    adapter = Keyword.get(mailer, :adapter, Swoosh.Adapters.Local)

    %__MODULE__{
      provider:
        case adapter do
          Swoosh.Adapters.Resend -> "resend"
          Swoosh.Adapters.SMTP -> "smtp"
          _ -> "local"
        end,
      enabled: Keyword.get(email, :enabled, true),
      from_name: email[:from_name] || "Algoie",
      from_address: email[:from_address] || "noreply@localhost",
      reply_to: email[:reply_to],
      app_url: AlgoieWeb.PublicURL.origin(),
      api_key_ciphertext: encrypt_key(mailer[:api_key]),
      smtp_host: mailer[:relay],
      smtp_port: mailer[:port] || 587,
      smtp_username: mailer[:username],
      smtp_password_ciphertext: encrypt_key(mailer[:password]),
      smtp_password_hint:
        if(mailer[:password], do: String.slice(to_string(mailer[:password]), -4, 4)),
      smtp_auth: to_string(mailer[:auth] || :if_available),
      smtp_tls: to_string(mailer[:tls] || :if_available)
    }
  end

  defp require_resend_key(changeset) do
    provider = get_field(changeset, :provider)
    existing_key = get_field(changeset, :api_key_ciphertext)
    new_key = get_change(changeset, :api_key)

    if provider == "resend" and blank?(new_key) and blank?(existing_key) do
      add_error(changeset, :api_key, "is required for Resend")
    else
      changeset
    end
  end

  defp require_smtp_credentials(changeset) do
    if get_field(changeset, :provider) == "smtp" do
      changeset
      |> validate_required([:smtp_host, :smtp_port, :smtp_username])
      |> require_existing_or_new_password()
    else
      changeset
    end
  end

  defp require_existing_or_new_password(changeset) do
    existing_password = get_field(changeset, :smtp_password_ciphertext)
    new_password = get_change(changeset, :smtp_password)

    if blank?(existing_password) and blank?(new_password) do
      add_error(changeset, :smtp_password, "is required for SMTP")
    else
      changeset
    end
  end

  defp encrypt_changed_credentials(changeset) do
    changeset =
      changeset
      |> encrypt_change(:api_key, :api_key_ciphertext)
      |> encrypt_change(:smtp_password, :smtp_password_ciphertext)

    case get_change(changeset, :smtp_password) do
      value when value in [nil, ""] -> changeset
      value -> put_change(changeset, :smtp_password_hint, String.slice(value, -4, 4))
    end
  end

  defp encrypt_change(changeset, source, target) do
    case get_change(changeset, source) do
      value when value in [nil, ""] -> changeset
      value -> put_change(changeset, target, encrypt_key(value))
    end
  end

  defp encrypt_key(value) when value in [nil, ""], do: nil

  defp encrypt_key(value) do
    Plug.Crypto.MessageEncryptor.encrypt(value, encryption_key(), "unused")
  end

  defp decrypt_key(value) when value in [nil, ""], do: nil

  defp decrypt_key(value) do
    case Plug.Crypto.MessageEncryptor.decrypt(value, encryption_key(), "unused") do
      {:ok, plain_text} -> plain_text
      :error -> nil
    end
  end

  defp encryption_key do
    secret = Application.fetch_env!(:algoie, AlgoieWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(secret, "platform email settings", length: 32)
  end

  defp blank?(value), do: value in [nil, ""]
  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp smtp_mode("always"), do: :always
  defp smtp_mode("never"), do: :never
  defp smtp_mode(_), do: :if_available
end
