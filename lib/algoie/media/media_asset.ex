defmodule Algoie.Media.MediaAsset do
  @moduledoc """
  A stored media file (image) belonging to a store's media library.

  Assets are uploaded through `Algoie.Media.Storage` to local disk or the
  platform's configured S3-compatible bucket and tracked
  here so they can be searched, reused across forms (products, brands,
  categories, ...), and deleted safely (removing both the DB row and the
  underlying file).
  """

  use Ash.Resource,
    domain: Algoie.Media,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("media_assets")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:folder_id, :uuid)
    attribute(:url, :string, allow_nil?: false)
    attribute(:filename, :string, allow_nil?: false)
    attribute(:content_type, :string)
    attribute(:size, :integer)
    attribute(:width, :integer)
    attribute(:height, :integer)
    attribute(:alt_text, :string)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :folder, Algoie.Media.MediaFolder
  end

  actions do
    read :read do
      primary?(true)
      pagination(offset?: true, default_limit: 24, countable: true, required?: false)
    end

    destroy :destroy do
      primary?(true)
    end

    create :create do
      primary?(true)

      accept([
        :store_id,
        :folder_id,
        :url,
        :filename,
        :content_type,
        :size,
        :width,
        :height,
        :alt_text
      ])
    end

    update :update do
      primary?(true)
      accept([:alt_text, :folder_id])
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "catalog"})
    end

    policy action_type([:read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "catalog"})
    end

    policy action_type(:destroy) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, area: "catalog"})
    end
  end
end
