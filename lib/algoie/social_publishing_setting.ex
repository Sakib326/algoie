defmodule Algoie.SocialPublishingSetting do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "social_publishing_settings" do
    field :active_adapter, :string, default: "zernio"
    field :api_key_ciphertext, :string
    field :api_key, :string, virtual: true, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def get,
    do: Repo.one(from(s in __MODULE__, order_by: [asc: s.inserted_at], limit: 1)) || %__MODULE__{}

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:active_adapter, :api_key])
    |> validate_inclusion(:active_adapter, ["zernio"])
    |> encrypt_key_change()
  end

  def save(attrs) do
    settings = get()
    changeset = changeset(settings, attrs)
    if settings.id, do: Repo.update(changeset), else: Repo.insert(changeset)
  end

  def api_key(%__MODULE__{api_key_ciphertext: value}) when value in [nil, ""], do: nil
  def api_key(%__MODULE__{api_key_ciphertext: value}), do: decrypt(value)
  def configured?(settings), do: settings.api_key_ciphertext not in [nil, ""]

  def masked_key(settings),
    do: if(configured?(settings), do: "•••• configured", else: "Not configured")

  defp encrypt_key_change(changeset) do
    case get_change(changeset, :api_key) do
      value when value in [nil, ""] -> changeset
      value -> put_change(changeset, :api_key_ciphertext, encrypt(value))
    end
  end

  defp encrypt(value), do: Plug.Crypto.MessageEncryptor.encrypt(value, encryption_key(), "unused")

  defp decrypt(value) do
    case Plug.Crypto.MessageEncryptor.decrypt(value, encryption_key(), "unused") do
      {:ok, plain} -> plain
      :error -> nil
    end
  end

  defp encryption_key do
    secret = Application.fetch_env!(:algoie, AlgoieWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(secret, "social publishing settings", length: 32)
  end
end
