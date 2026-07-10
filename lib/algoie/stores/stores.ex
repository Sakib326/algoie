defmodule Algoie.Stores do
  use Ash.Domain
  import Ecto.Query, only: [from: 2]

  resources do
    resource(Algoie.Stores.Store)
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

      {:error, err} ->
        IO.puts("DEBUG create_registry_entry error: #{inspect(err)}")
        :ok
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

  @doc """
  Look up a store by slug in the public registry.
  Returns {:ok, %{tenant_id, store_id}} or {:error, :not_found}.
  """
  def lookup_store_by_slug(slug) do
    case Algoie.Repo.one(
           from(r in __MODULE__.StoreRegistry,
             prefix: "public",
             where: r.slug == ^slug,
             select: %{tenant_id: r.tenant_id, store_id: r.store_id}
           )
         ) do
      %{tenant_id: tenant_id, store_id: store_id} ->
        {:ok, %{tenant_id: tenant_id, store_id: store_id}}

      nil ->
        {:error, :not_found}
    end
  end
end
