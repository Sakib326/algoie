defmodule Algoie.PlatformAISettings do
  @moduledoc """
  Database-backed, SaaS-admin-managed OpenRouter configuration.

  The plaintext key is virtual and is encrypted before persistence. Callers use
  `openrouter_api_key/1` only inside the server-side provider adapter.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "platform_ai_settings" do
    field :enabled, :boolean, default: false
    field :openrouter_api_key_ciphertext, :string
    field :openrouter_api_key, :string, virtual: true, redact: true
    field :default_model, :string, default: ""
    field :fallback_model, :string
    field :monthly_budget_cents, :integer
    field :max_run_cost_cents, :integer, default: 25
    field :allowed_models, {:array, :string}, default: []
    field :allowed_models_text, :string, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  def get do
    Repo.one(from(settings in __MODULE__, order_by: [asc: settings.inserted_at], limit: 1)) ||
      %__MODULE__{}
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :enabled,
      :openrouter_api_key,
      :default_model,
      :fallback_model,
      :monthly_budget_cents,
      :max_run_cost_cents,
      :allowed_models,
      :allowed_models_text
    ])
    |> normalize_models()
    |> validate_number(:monthly_budget_cents, greater_than: 0)
    |> validate_number(:max_run_cost_cents, greater_than: 0)
    |> validate_enabled_configuration()
    |> encrypt_key_change()
  end

  def save(attrs) do
    settings = get()
    changeset = changeset(settings, attrs)

    if settings.id do
      Repo.update(changeset)
    else
      Repo.insert(changeset)
    end
  end

  def configured?(%__MODULE__{} = settings) do
    settings.enabled and configured_key?(settings) and settings.default_model not in [nil, ""]
  end

  def configured_key?(%__MODULE__{openrouter_api_key_ciphertext: key}), do: key not in [nil, ""]

  def masked_key(%__MODULE__{openrouter_api_key_ciphertext: key}) when key not in [nil, ""],
    do: "•••• configured"

  def masked_key(_settings), do: "Not configured"

  def openrouter_api_key(%__MODULE__{openrouter_api_key_ciphertext: ciphertext}) do
    decrypt(ciphertext)
  end

  def allowed_model?(%__MODULE__{} = settings, model) when is_binary(model) do
    model in settings.allowed_models
  end

  defp normalize_models(changeset) do
    models =
      case get_change(changeset, :allowed_models_text) do
        value when is_binary(value) -> String.split(value, ~r/[\n,]/, trim: true)
        _ -> get_change(changeset, :allowed_models)
      end

    case models do
      nil ->
        changeset

      models when is_list(models) ->
        models =
          models
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        changeset
        |> put_change(:allowed_models, models)
        |> put_change(:allowed_models_text, Enum.join(models, "\n"))
    end
  end

  defp validate_enabled_configuration(changeset) do
    if get_field(changeset, :enabled) do
      changeset
      |> validate_required([:default_model])
      |> require_existing_or_new_key()
      |> ensure_default_model_allowed()
      |> ensure_fallback_model_allowed()
    else
      changeset
    end
  end

  defp require_existing_or_new_key(changeset) do
    if get_field(changeset, :openrouter_api_key_ciphertext) in [nil, ""] and
         get_change(changeset, :openrouter_api_key) in [nil, ""] do
      add_error(changeset, :openrouter_api_key, "is required while AI is enabled")
    else
      changeset
    end
  end

  defp ensure_default_model_allowed(changeset) do
    allowed = get_field(changeset, :allowed_models)
    model = get_field(changeset, :default_model)

    if model in allowed,
      do: changeset,
      else: add_error(changeset, :default_model, "must be in allowed models")
  end

  defp ensure_fallback_model_allowed(changeset) do
    fallback = get_field(changeset, :fallback_model)
    allowed = get_field(changeset, :allowed_models)

    if fallback in [nil, ""] or fallback in allowed,
      do: changeset,
      else: add_error(changeset, :fallback_model, "must be in allowed models")
  end

  defp encrypt_key_change(changeset) do
    case get_change(changeset, :openrouter_api_key) do
      value when value in [nil, ""] -> changeset
      value -> put_change(changeset, :openrouter_api_key_ciphertext, encrypt(value))
    end
  end

  defp encrypt(value), do: Plug.Crypto.MessageEncryptor.encrypt(value, encryption_key(), "unused")
  defp decrypt(value) when value in [nil, ""], do: nil

  defp decrypt(value) do
    case Plug.Crypto.MessageEncryptor.decrypt(value, encryption_key(), "unused") do
      {:ok, plain_text} -> plain_text
      :error -> nil
    end
  end

  defp encryption_key do
    secret = Application.fetch_env!(:algoie, AlgoieWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(secret, "platform AI settings", length: 32)
  end
end
