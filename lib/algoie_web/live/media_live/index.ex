defmodule AlgoieWeb.MediaLive.Index do
  @moduledoc """
  Store-wide media library: WordPress-style manager with folders, search,
  upload, and a details panel for editing/organizing/deleting files used
  across products, brands, categories, and any other form.
  """

  use AlgoieWeb, :live_view

  alias Algoie.Media
  alias Algoie.Media.Storage

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :media)
     |> assign(:page_title, "Media Library")
     |> assign(:query, "")
     |> assign(:show_uploader, false)
     |> assign(:current_folder, :all)
     |> assign(:creating_folder, false)
     |> assign(:editing_folder_id, nil)
     |> assign(:selected_asset, nil)
     |> assign(:folders, Media.list_folders(opts(socket)))
     |> assign(:counts, Media.folder_counts(opts(socket)))
     |> assign(:page, 1)
     |> assign(:assets_page, nil)
     |> assign(:assets, [])
     |> allow_upload(:media,
       accept: Storage.accepted_extensions(),
       max_entries: 24,
       max_file_size: Storage.max_file_size(),
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {p, _} when p > 0 -> p
        _ -> 1
      end

    socket =
      socket
      |> assign(:page, page)
      |> load_assets()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-uploader", _params, socket) do
    {:noreply, assign(socket, :show_uploader, !socket.assigns.show_uploader)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"value" => query}, socket) do
    socket = assign(socket, :query, query) |> assign(:page, 1)
    {:noreply, load_assets(socket)}
  end

  def handle_event("cancel-entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  # ── Folder navigation ────────────────────────────────────────────

  def handle_event("select-folder", %{"id" => id}, socket) do
    socket =
      socket
      |> assign(:current_folder, parse_folder(id))
      |> assign(:selected_asset, nil)

    {:noreply, load_assets(socket)}
  end

  def handle_event("new-folder-start", _params, socket) do
    {:noreply, assign(socket, :creating_folder, true)}
  end

  def handle_event("new-folder-cancel", _params, socket) do
    {:noreply, assign(socket, :creating_folder, false)}
  end

  def handle_event("new-folder-save", %{"name" => name}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, assign(socket, :creating_folder, false)}

      trimmed ->
        Media.create_folder(%{name: trimmed, store_id: socket.assigns.store_id}, opts(socket))
        {:noreply, socket |> assign(:creating_folder, false) |> reload_folders()}
    end
  end

  def handle_event("rename-folder-start", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_folder_id, id)}
  end

  def handle_event("rename-folder-cancel", _params, socket) do
    {:noreply, assign(socket, :editing_folder_id, nil)}
  end

  def handle_event("rename-folder-save", %{"id" => id, "name" => name}, socket) do
    with trimmed when trimmed != "" <- String.trim(name),
         {:ok, folder} <- Media.get_folder(id, opts(socket)) do
      Media.rename_folder(folder, trimmed, opts(socket))
    end

    {:noreply, socket |> assign(:editing_folder_id, nil) |> reload_folders()}
  end

  def handle_event("delete-folder", %{"id" => id}, socket) do
    socket =
      case Media.get_folder(id, opts(socket)) do
        {:ok, folder} ->
          Media.delete_folder(folder, opts(socket))

          current =
            if socket.assigns.current_folder == id, do: :all, else: socket.assigns.current_folder

          socket |> assign(:current_folder, current) |> reload_folders()

        _ ->
          socket
      end

    {:noreply, load_assets(socket)}
  end

  # ── Asset details panel ──────────────────────────────────────────

  def handle_event("open-asset", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_asset, Enum.find(socket.assigns.assets, &(&1.id == id)))}
  end

  def handle_event("close-details", _params, socket) do
    {:noreply, assign(socket, :selected_asset, nil)}
  end

  def handle_event("save-alt-text", %{"id" => id, "alt_text" => alt_text}, socket) do
    with {:ok, asset} <- Media.get_asset(id, opts(socket)),
         {:ok, updated} <- Media.update_asset(asset, %{alt_text: alt_text}, opts(socket)) do
      {:noreply,
       socket
       |> assign(:selected_asset, updated)
       |> assign(:assets, replace_asset(socket.assigns.assets, updated))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move-asset", %{"id" => id, "folder_id" => folder_id}, socket) do
    folder_id = if folder_id == "", do: nil, else: folder_id

    with {:ok, asset} <- Media.get_asset(id, opts(socket)),
         {:ok, updated} <- Media.move_asset(asset, folder_id, opts(socket)) do
      socket = reload_folders(socket)

      assets =
        if matches_folder?(updated, socket.assigns.current_folder),
          do: replace_asset(socket.assigns.assets, updated),
          else: Enum.reject(socket.assigns.assets, &(&1.id == updated.id))

      {:noreply, socket |> assign(:selected_asset, updated) |> assign(:assets, assets)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete-asset", %{"id" => id}, socket) do
    case Media.get_asset(id, opts(socket)) do
      {:ok, asset} ->
        Media.delete_asset(asset, opts(socket))

        selected =
          if socket.assigns.selected_asset && socket.assigns.selected_asset.id == id,
            do: nil,
            else: socket.assigns.selected_asset

        {:noreply,
         socket
         |> assign(:assets, Enum.reject(socket.assigns.assets, &(&1.id == id)))
         |> assign(:selected_asset, selected)
         |> reload_folders()
         |> put_flash(:info, "File deleted")}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_progress(:media, entry, socket) do
    if entry.done? do
      tenant = socket.assigns.tenant
      folder_id = real_folder_id(socket.assigns.current_folder)

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          with {:ok, info} <- Storage.put(tenant, path, entry.client_name),
               {:ok, asset} <-
                 Media.create_asset(
                   %{
                     store_id: socket.assigns.store_id,
                     folder_id: folder_id,
                     url: info.url,
                     filename: info.filename,
                     content_type: entry.client_type,
                     size: info.size
                   },
                   opts(socket)
                 ) do
            {:ok, {:ok, asset}}
          else
            {:error, reason} -> {:ok, {:error, reason}}
          end
        end)

      case result do
        {:ok, asset} ->
          {:noreply,
           socket
           |> assign(:assets, [asset | socket.assigns.assets])
           |> reload_folders()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to upload #{entry.client_name}")}
      end
    else
      {:noreply, socket}
    end
  end

  defp opts(socket), do: AlgoieWeb.Scope.opts(socket)

  defp load_assets(socket) do
    limit = 24
    offset = (socket.assigns.page - 1) * limit
    opts = Keyword.put(opts(socket), :page, offset: offset, count: true)

    case Media.list_assets(opts, socket.assigns.query, socket.assigns.current_folder) do
      %Ash.Page.Offset{} = page_result ->
        socket
        |> assign(:assets, page_result.results)
        |> assign(:assets_page, page_result)

      results when is_list(results) ->
        socket
        |> assign(:assets, results)
        |> assign(:assets_page, nil)

      _ ->
        socket
        |> assign(:assets, [])
        |> assign(:assets_page, nil)
    end
  end

  defp reload_folders(socket) do
    socket
    |> assign(:folders, Media.list_folders(opts(socket)))
    |> assign(:counts, Media.folder_counts(opts(socket)))
  end

  defp parse_folder("all"), do: :all
  defp parse_folder("unfiled"), do: :unfiled
  defp parse_folder(id), do: id

  defp real_folder_id(:all), do: nil
  defp real_folder_id(:unfiled), do: nil
  defp real_folder_id(id), do: id

  defp matches_folder?(_asset, :all), do: true
  defp matches_folder?(asset, :unfiled), do: is_nil(asset.folder_id)
  defp matches_folder?(asset, folder_id), do: asset.folder_id == folder_id

  defp replace_asset(assets, updated) do
    Enum.map(assets, fn a -> if a.id == updated.id, do: updated, else: a end)
  end

  defp format_size(nil), do: nil
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_date(nil), do: nil
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")

  defp folder_options(folders) do
    [{"Unfiled", ""} | Enum.map(folders, &{&1.name, &1.id})]
  end
end
