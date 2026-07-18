defmodule Algoie.Media do
  @moduledoc """
  Domain for the store media library (uploaded images used across products,
  brands, categories, and any other form that embeds
  `AlgoieWeb.Components.MediaManagerComponent`).
  """

  use Ash.Domain

  resources do
    resource(Algoie.Media.MediaAsset)
    resource(Algoie.Media.MediaFolder)
  end

  require Ash.Query

  @doc """
  Lists media assets for the current store, most recent first, optionally
  filtered by a search query and/or a folder scope.

  `folder` is one of:

    * `:all` (default) — every asset regardless of folder
    * `:unfiled` — only assets with no folder
    * a folder id — only assets inside that folder
  """
  def list_assets(opts, query \\ nil, folder \\ :all) do
    Algoie.Media.MediaAsset
    |> Ash.Query.sort(inserted_at: :desc)
    |> maybe_filter(query)
    |> maybe_scope_folder(folder)
    |> Ash.read(opts)
    |> case do
      {:ok, result} -> result
      {:error, _} -> []
    end
  end

  defp maybe_filter(query_ash, nil), do: query_ash
  defp maybe_filter(query_ash, ""), do: query_ash

  defp maybe_filter(query_ash, search) do
    Ash.Query.filter(query_ash, contains(filename, ^search) or contains(alt_text, ^search))
  end

  defp maybe_scope_folder(query_ash, :all), do: query_ash
  defp maybe_scope_folder(query_ash, :unfiled), do: Ash.Query.filter(query_ash, is_nil(folder_id))

  defp maybe_scope_folder(query_ash, folder_id),
    do: Ash.Query.filter(query_ash, folder_id == ^folder_id)

  @doc """
  Persists an uploaded file's metadata as a `MediaAsset`.
  """
  def create_asset(attrs, opts) do
    Ash.create(Algoie.Media.MediaAsset, attrs, opts)
  end

  @doc """
  Moves an asset into `folder_id` (`nil` to unfile it).
  """
  def move_asset(%Algoie.Media.MediaAsset{} = asset, folder_id, opts) do
    Ash.update(asset, %{folder_id: folder_id}, opts)
  end

  @doc """
  Updates alt text/metadata for an asset.
  """
  def update_asset(%Algoie.Media.MediaAsset{} = asset, attrs, opts) do
    Ash.update(asset, attrs, opts)
  end

  @doc """
  Destroys a media asset and removes the underlying file from disk.
  """
  def delete_asset(%Algoie.Media.MediaAsset{} = asset, opts) do
    case Ash.destroy(asset, opts) do
      :ok ->
        Algoie.Media.Storage.delete(asset.url)
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  def get_asset(id, opts) do
    Ash.get(Algoie.Media.MediaAsset, id, opts)
  end

  # ── Folders ───────────────────────────────────────────────────────

  @doc "Lists all folders for the store, alphabetically."
  def list_folders(opts) do
    Algoie.Media.MediaFolder
    |> Ash.Query.sort(name: :asc)
    |> Ash.read(opts)
    |> case do
      {:ok, folders} -> folders
      {:error, _} -> []
    end
  end

  @doc "Creates a folder."
  def create_folder(attrs, opts) do
    Ash.create(Algoie.Media.MediaFolder, attrs, opts)
  end

  def get_folder(id, opts) do
    Ash.get(Algoie.Media.MediaFolder, id, opts)
  end

  @doc "Renames a folder."
  def rename_folder(%Algoie.Media.MediaFolder{} = folder, name, opts) do
    Ash.update(folder, %{name: name}, opts)
  end

  @doc """
  Deletes a folder. Any assets inside are unfiled (moved to `folder_id:
  nil`) and any subfolders are reparented to the root — nothing is ever
  deleted implicitly except the folder record itself.
  """
  def delete_folder(%Algoie.Media.MediaFolder{} = folder, opts) do
    opts
    |> Keyword.put(:page, false)
    |> list_assets(nil, folder.id)
    |> case do
      %Ash.Page.Offset{} = page -> page.results
      results when is_list(results) -> results
    end
    |> Enum.each(&move_asset(&1, nil, opts))

    opts
    |> list_folders()
    |> Enum.filter(&(&1.parent_id == folder.id))
    |> Enum.each(&Ash.update(&1, %{parent_id: nil}, opts))

    Ash.destroy(folder, opts)
  end

  @doc """
  Returns `%{all: count, unfiled: count, folders: %{folder_id => count}}`
  for building the folder sidebar without N+1 queries.
  """
  def folder_counts(opts) do
    opts = Keyword.put(opts, :page, false)
    
    Algoie.Media.MediaAsset
    |> Ash.Query.select([:folder_id])
    |> Ash.read(opts)
    |> case do
      {:ok, %Ash.Page.Offset{} = page} ->
        assets = page.results
        by_folder = Enum.frequencies_by(assets, & &1.folder_id)

        %{
          all: length(assets),
          unfiled: Map.get(by_folder, nil, 0),
          folders: Map.delete(by_folder, nil)
        }

      {:ok, assets} when is_list(assets) ->
        by_folder = Enum.frequencies_by(assets, & &1.folder_id)

        %{
          all: length(assets),
          unfiled: Map.get(by_folder, nil, 0),
          folders: Map.delete(by_folder, nil)
        }

      {:error, _} ->
        %{all: 0, unfiled: 0, folders: %{}}
    end
  end
end
