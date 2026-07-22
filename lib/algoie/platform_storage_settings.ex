defmodule Algoie.PlatformStorageSettings do
  @moduledoc "SaaS-admin-managed local or S3-compatible media storage configuration."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "platform_storage_settings" do
    field :backend, :string, default: "local"
    field :endpoint, :string
    field :region, :string
    field :bucket, :string
    field :access_key_id, :string
    field :secret_access_key_ciphertext, :string
    field :secret_access_key, :string, virtual: true, redact: true
    field :public_base_url, :string
    field :path_style, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def get do
    Repo.one(from(s in __MODULE__, order_by: [asc: s.inserted_at], limit: 1)) || %__MODULE__{}
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :backend,
      :endpoint,
      :region,
      :bucket,
      :access_key_id,
      :secret_access_key,
      :public_base_url,
      :path_style
    ])
    |> update_change(:endpoint, &trim_url/1)
    |> update_change(:public_base_url, &trim_url/1)
    |> validate_inclusion(:backend, ~w(local s3))
    |> validate_url(:endpoint)
    |> validate_url(:public_base_url)
    |> validate_s3()
    |> encrypt_secret_change()
  end

  def save(attrs) do
    settings = get()
    changeset = changeset(settings, attrs)
    if settings.id, do: Repo.update(changeset), else: Repo.insert(changeset)
  end

  def s3?(%__MODULE__{backend: "s3"} = settings), do: configured?(settings)
  def s3?(_settings), do: false
  def configured?(%__MODULE__{backend: "local"}), do: true

  def configured?(%__MODULE__{} = settings) do
    Enum.all?(
      [settings.endpoint, settings.region, settings.bucket, settings.access_key_id],
      &(&1 not in [nil, ""])
    ) and configured_secret?(settings)
  end

  def configured_secret?(%__MODULE__{secret_access_key_ciphertext: value}),
    do: value not in [nil, ""]

  def masked_secret(settings),
    do: if(configured_secret?(settings), do: "•••• configured", else: "Not configured")

  def secret_access_key(%__MODULE__{secret_access_key_ciphertext: value}), do: decrypt(value)

  defp validate_s3(changeset) do
    if get_field(changeset, :backend) == "s3" do
      changeset
      |> validate_required([:endpoint, :region, :bucket, :access_key_id])
      |> validate_format(:bucket, ~r/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/,
        message: "must be a valid S3 bucket name"
      )
      |> require_secret()
    else
      changeset
    end
  end

  defp require_secret(changeset) do
    if get_field(changeset, :secret_access_key_ciphertext) in [nil, ""] and
         get_change(changeset, :secret_access_key) in [nil, ""] do
      add_error(changeset, :secret_access_key, "is required for S3 storage")
    else
      changeset
    end
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      uri = URI.parse(value || "")

      if value in [nil, ""] or (uri.scheme in ["http", "https"] and is_binary(uri.host)),
        do: [],
        else: [{field, "must be a complete HTTP or HTTPS URL"}]
    end)
  end

  defp encrypt_secret_change(changeset) do
    case get_change(changeset, :secret_access_key) do
      value when value in [nil, ""] -> changeset
      value -> put_change(changeset, :secret_access_key_ciphertext, encrypt(value))
    end
  end

  defp trim_url(nil), do: nil

  defp trim_url(value) do
    case value |> String.trim() |> String.trim_trailing("/") do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp encrypt(value), do: Plug.Crypto.MessageEncryptor.encrypt(value, encryption_key(), "unused")
  defp decrypt(value) when value in [nil, ""], do: nil

  defp decrypt(value) do
    case Plug.Crypto.MessageEncryptor.decrypt(value, encryption_key(), "unused") do
      {:ok, plain} -> plain
      :error -> nil
    end
  end

  defp encryption_key do
    secret = Application.fetch_env!(:algoie, AlgoieWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(secret, "platform storage settings", length: 32)
  end
end
