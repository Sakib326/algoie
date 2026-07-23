defmodule Algoie.SocialPublishing.AccountRegistry do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "social_account_registry" do
    field :provider_account_id, :string
    field :tenant, :string
    field :store_id, Ecto.UUID
    field :local_account_id, Ecto.UUID
    field :platform, :string
    timestamps(type: :utc_datetime_usec)
  end

  def upsert(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:provider_account_id, :tenant, :store_id, :local_account_id, :platform])
    |> validate_required([:provider_account_id, :tenant, :store_id, :local_account_id, :platform])
    |> Repo.insert(
      conflict_target: :provider_account_id,
      on_conflict: {:replace, [:tenant, :store_id, :local_account_id, :platform, :updated_at]}
    )
  end

  def get(provider_account_id) when is_binary(provider_account_id) do
    Repo.one(from r in __MODULE__, where: r.provider_account_id == ^provider_account_id)
  end

  def delete(provider_account_id) when is_binary(provider_account_id) do
    Repo.delete_all(from r in __MODULE__, where: r.provider_account_id == ^provider_account_id)
    :ok
  end
end
