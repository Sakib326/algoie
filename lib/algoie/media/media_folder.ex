defmodule Algoie.Media.MediaFolder do
  @moduledoc """
  A folder used to organize a store's media library (WordPress-style
  folders). Folders can be nested one level via `parent_id` and hold any
  number of `Algoie.Media.MediaAsset` records.
  """

  use Ash.Resource,
    domain: Algoie.Media,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("media_folders")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:name, :string, allow_nil?: false)
    attribute(:parent_id, :uuid)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :parent, Algoie.Media.MediaFolder
    has_many :children, Algoie.Media.MediaFolder, destination_attribute: :parent_id
    has_many :assets, Algoie.Media.MediaAsset, destination_attribute: :folder_id
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:name, :store_id, :parent_id])
    end

    update :update do
      primary?(true)
      accept([:name, :parent_id])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end

    policy action_type([:read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end

    policy action_type(:destroy) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end
  end
end
