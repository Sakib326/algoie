defmodule Algoie.StoreEmailSettings do
  @moduledoc "Per-store SMTP configuration with encrypted credentials and platform fallback."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "store_email_settings" do
    field :store_id, :binary_id
    field :use_platform, :boolean, default: true
    field :enabled, :boolean, default: true
    field :smtp_host, :string
    field :smtp_port, :integer, default: 587
    field :smtp_username, :string
    field :smtp_password_ciphertext, :string
    field :smtp_password_hint, :string
    field :smtp_password, :string, virtual: true, redact: true
    field :smtp_auth, :string, default: "if_available"
    field :smtp_tls, :string, default: "if_available"
    field :from_name, :string
    field :from_address, :string
    field :reply_to, :string
    timestamps(type: :utc_datetime_usec)
  end

  def get(tenant, store_id) do
    Repo.one(from(settings in __MODULE__, where: settings.store_id == ^store_id, limit: 1),
      prefix: tenant
    ) ||
      %__MODULE__{store_id: store_id}
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :use_platform,
      :enabled,
      :smtp_host,
      :smtp_port,
      :smtp_username,
      :smtp_password,
      :smtp_auth,
      :smtp_tls,
      :from_name,
      :from_address,
      :reply_to
    ])
    |> validate_number(:smtp_port, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_inclusion(:smtp_auth, ["always", "if_available", "never"])
    |> validate_inclusion(:smtp_tls, ["always", "if_available", "never"])
    |> validate_custom_configuration()
    |> encrypt_changed_password()
  end

  def save(tenant, store_id, attrs) do
    settings = get(tenant, store_id)
    changeset = changeset(settings, attrs)

    if settings.id,
      do: Repo.update(changeset, prefix: tenant),
      else: changeset |> put_change(:store_id, store_id) |> Repo.insert(prefix: tenant)
  end

  def reset_credentials(tenant, store_id) do
    case get(tenant, store_id) do
      %__MODULE__{id: nil} = settings ->
        {:ok, settings}

      settings ->
        settings
        |> change(smtp_password_ciphertext: nil, smtp_password_hint: nil)
        |> Repo.update(prefix: tenant)
    end
  end

  def configured?(settings) do
    not settings.use_platform and settings.smtp_host not in [nil, ""] and
      settings.smtp_username not in [nil, ""] and
      settings.smtp_password_ciphertext not in [nil, ""]
  end

  def masked_password(%__MODULE__{smtp_password_hint: hint}) when hint not in [nil, ""],
    do: "••••#{hint}"

  def masked_password(_settings), do: "Not configured"

  def delivery_config(settings) do
    %{
      enabled: settings.enabled,
      source: :store,
      mailer: [
        adapter: Swoosh.Adapters.SMTP,
        relay: settings.smtp_host,
        port: settings.smtp_port,
        username: settings.smtp_username,
        password: decrypt(settings.smtp_password_ciphertext),
        auth: smtp_mode(settings.smtp_auth),
        tls: smtp_mode(settings.smtp_tls),
        tls_options: Algoie.EmailRuntime.smtp_tls_options(settings.smtp_host),
        ssl: false
      ],
      email: [
        from_name: settings.from_name,
        from_address: settings.from_address,
        reply_to: blank_to_nil(settings.reply_to),
        app_url: Application.get_env(:algoie, :email, [])[:app_url]
      ]
    }
  end

  defp validate_custom_configuration(changeset) do
    if get_field(changeset, :use_platform) do
      changeset
    else
      changeset
      |> validate_required([:smtp_host, :smtp_port, :smtp_username, :from_name, :from_address])
      |> validate_format(:from_address, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
      |> validate_format(:reply_to, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
      |> require_password()
    end
  end

  defp require_password(changeset) do
    if get_field(changeset, :smtp_password_ciphertext) in [nil, ""] and
         get_change(changeset, :smtp_password) in [nil, ""],
       do: add_error(changeset, :smtp_password, "is required for custom SMTP"),
       else: changeset
  end

  defp encrypt_changed_password(changeset) do
    case get_change(changeset, :smtp_password) do
      value when value in [nil, ""] ->
        changeset

      value ->
        changeset
        |> put_change(:smtp_password_ciphertext, encrypt(value))
        |> put_change(:smtp_password_hint, String.slice(value, -4, 4))
    end
  end

  defp encrypt(value), do: Plug.Crypto.MessageEncryptor.encrypt(value, encryption_key(), "unused")

  defp decrypt(value) do
    case Plug.Crypto.MessageEncryptor.decrypt(value, encryption_key(), "unused") do
      {:ok, plain_text} -> plain_text
      :error -> nil
    end
  end

  defp encryption_key do
    secret = Application.fetch_env!(:algoie, AlgoieWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(secret, "store email settings", length: 32)
  end

  defp smtp_mode("always"), do: :always
  defp smtp_mode("never"), do: :never
  defp smtp_mode(_), do: :if_available
  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
