defmodule Algoie.Stores do
  use Ash.Domain
  import Ecto.Query, only: [from: 2]

  resources do
    resource(Algoie.Stores.Store)
    resource(Algoie.Stores.DeliveryCharge)
    resource(Algoie.Stores.StoreRegistry)
  end

  @doc """
  Create a registry entry for a newly created Store.
  Called from Store's after_action hook.
  Bypasses Ash to avoid tenant context propagation.
  """
  def create_registry_entry(store) do
    tenant_id = store.__metadata__.tenant |> String.replace_leading("tenant_", "")
    store_id = store.id

    %Algoie.Stores.StoreRegistry{}
    |> Ecto.Changeset.cast(
      %{
        slug: store.slug,
        tenant_id: tenant_id,
        store_id: store_id
      },
      [:slug, :tenant_id, :store_id]
    )
    |> Algoie.Repo.insert(prefix: "public")
    |> case do
      {:ok, _} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Delete a registry entry when a Store is destroyed.
  """
  def delete_registry_entry(store) do
    Algoie.Repo.delete_all(
      from(r in __MODULE__.StoreRegistry,
        prefix: "public",
        where: r.slug == ^store.slug
      )
    )
  end

  @doc "Keeps the public subdomain registry in sync when a store slug changes."
  def update_registry_entry(store) do
    tenant_id = store.__metadata__.tenant |> String.replace_leading("tenant_", "")

    case Algoie.Repo.one(
           from(r in __MODULE__.StoreRegistry,
             prefix: "public",
             where: r.store_id == ^store.id and r.tenant_id == ^tenant_id
           )
         ) do
      nil ->
        create_registry_entry(store)

      registry ->
        registry
        |> Ecto.Changeset.change(slug: store.slug)
        |> Ecto.Changeset.unique_constraint(:slug)
        |> Algoie.Repo.update(prefix: "public")
        |> case do
          {:ok, _} -> :ok
          {:error, error} -> {:error, error}
        end
    end
  end

  @doc """
  Look up a store by slug in the public registry.
  Returns {:ok, %{tenant_id, store_id}} or {:error, :not_found}.
  """
  def lookup_store_by_slug(slug) do
    case Algoie.Repo.query!(
           """
           SELECT r.tenant_id, r.store_id::text
           FROM public.store_registry r
           JOIN public.tenants t ON t.id::text = r.tenant_id
           WHERE r.slug = $1 AND t.billing_status != 'suspended'
           LIMIT 1
           """,
           [slug]
         ).rows do
      [[tenant_id, store_id]] ->
        {:ok, %{tenant_id: tenant_id, store_id: store_id}}

      [] ->
        {:error, :not_found}
    end
  end
end
