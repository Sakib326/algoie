defmodule AlgoieWeb.Components.MediaManagerComponent do
  @moduledoc """
  A reusable, drop-in media manager/picker for any dashboard form.

  It renders a preview grid of the currently selected image(s), an "Add
  media" tile that opens a modal with two tabs — **Upload** (drag & drop or
  browse, auto-uploads to the store's media library) and **Library**
  (search/select/delete previously uploaded files) — and hidden `<input>`
  fields so the selection travels with the surrounding `<.form>` on submit
  with zero extra parent wiring.

  ## Usage

      <.live_component
        module={AlgoieWeb.Components.MediaManagerComponent}
        id="product-images"
        field={@form[:images]}
        multiple
        max_selected={8}
        label="Product images"
        helper="The first image is used as the cover photo."
        store_id={@store_id}
        tenant={@tenant}
        current_user={@current_user}
      />

  For a single-image field (e.g. a brand logo), pass `multiple={false}` and
  omit `max_selected`.

  Resources with an `{:array, :string}` field populated this way should
  strip blank entries on create/update (needed to support clearing the list
  to `[]`) — see `Algoie.Media.Changes.RejectBlankValues`.

  ## Auto-submitting the wrapping form

  If the surrounding LiveView keeps ephemeral/staged state (e.g. a wizard
  that only persists on an explicit "Publish" step), pass `form` with a CSS
  selector for the wrapping `<form>` (which must have a matching `id`).
  When given, selecting/removing/reordering images immediately dispatches a
  `submit` on that form, so the parent's staged state is updated right away
  instead of waiting for a separate manual "Save" click. This matters
  because `update/2` re-applies whatever `selected` the parent last passed
  in on *every* parent re-render — without an immediate submit, an
  unrelated parent-level event could silently reset picks the user hasn't
  explicitly saved yet.

      <form id="product-images-form" phx-submit="save_product_images">
        <.live_component
          module={AlgoieWeb.Components.MediaManagerComponent}
          id="product-images"
          name="product_images"
          form="#product-images-form"
          multiple
          store_id={@store_id}
          tenant={@tenant}
          current_user={@current_user}
        />
      </form>
  """

  use AlgoieWeb, :live_component

  alias Algoie.Media
  alias Algoie.Media.Storage

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_modal, false)
     |> assign(:tab, "library")
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:assets_page, nil)
     |> assign(:staged, [])
     |> assign(:current_folder, :all)
     |> assign(:creating_folder, false)
     |> assign(:editing_folder_id, nil)
     |> allow_upload(:media,
       accept: Storage.accepted_extensions(),
       max_entries: 24,
       max_file_size: Storage.max_file_size(),
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def update(assigns, socket) do
    # Build the new selected from parent assigns (used only when it actually changed)
    incoming_selected =
      cond do
        field = assigns[:field] ->
          field.value |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

        value = assigns[:selected] ->
          value |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

        true ->
          []
      end

    # Only overwrite local `selected` if the parent actually sent a different list.
    # This prevents a parent re-render (triggered by *any* event) from resetting
    # selections the user just made inside this component.
    current_selected = socket.assigns[:selected]

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:multiple, fn -> true end)
      |> assign_new(:max_selected, fn -> nil end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:helper, fn -> nil end)
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:field, fn -> nil end)
      |> assign_new(:form, fn -> nil end)
      |> assign_new(:folders, fn -> Media.list_folders(socket_opts(assigns)) end)
      |> assign_new(:counts, fn -> Media.folder_counts(socket_opts(assigns)) end)
      |> assign_new(:assets_page, fn -> load_assets_page(socket_opts(assigns), nil, :all, 1) end)
      |> assign_new(:assets, fn ->
        case load_assets_page(socket_opts(assigns), nil, :all, 1) do
          %Ash.Page.Offset{} = page -> page.results
          list when is_list(list) -> list
          _ -> []
        end
      end)

    # Restore local selected if parent didn't actually change the list
    socket =
      if is_nil(current_selected) or current_selected == incoming_selected do
        # First render or parent intentionally synced a new list — accept it
        assign(socket, :selected, incoming_selected)
      else
        # Parent re-render with stale snapshot — keep the locally-staged selection
        assign(socket, :selected, current_selected)
      end

    {:ok, socket}
  end

  # ── Events ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("open-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:staged, socket.assigns.selected)
     |> assign(:query, "")
     |> assign(:current_folder, :all)
     |> assign(:page, 1)
     |> reload_folders()
     |> reload_assets()}
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  def handle_event("set-tab", %{"tab" => tab}, socket) when tab in ["library", "upload"] do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:page, 1)
     |> reload_assets()}
  end

  def handle_event("toggle-asset", %{"url" => url}, socket) do
    staged =
      toggle_url(socket.assigns.staged, url, socket.assigns.multiple, socket.assigns.max_selected)

    {:noreply, assign(socket, :staged, staged)}
  end

  # ── Folder navigation ──────────────────────────────────────────────

  def handle_event("select-folder", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:current_folder, parse_folder(id))
     |> assign(:page, 1)
     |> reload_assets()}
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
        Media.create_folder(
          %{name: trimmed, store_id: socket.assigns.store_id},
          socket_opts(socket.assigns)
        )

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
         {:ok, folder} <- Media.get_folder(id, socket_opts(socket.assigns)) do
      Media.rename_folder(folder, trimmed, socket_opts(socket.assigns))
    end

    {:noreply, socket |> assign(:editing_folder_id, nil) |> reload_folders()}
  end

  def handle_event("delete-folder", %{"id" => id}, socket) do
    socket =
      case Media.get_folder(id, socket_opts(socket.assigns)) do
        {:ok, folder} ->
          Media.delete_folder(folder, socket_opts(socket.assigns))

          current =
            if socket.assigns.current_folder == id, do: :all, else: socket.assigns.current_folder

          socket |> assign(:current_folder, current) |> reload_folders()

        _ ->
          socket
      end

    {:noreply, reload_assets(socket)}
  end

  def handle_event("set-page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {p, _} when p > 0 -> p
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> reload_assets()}
  end

  def handle_event("confirm-selection", _params, socket) do
    notify_parent(socket, socket.assigns.staged)

    {:noreply,
     socket
     |> assign(:selected, socket.assigns.staged)
     |> assign(:show_modal, false)}
  end

  def handle_event("remove-selected", %{"url" => url}, socket) do
    new_selected = Enum.reject(socket.assigns.selected, &(&1 == url))
    notify_parent(socket, new_selected)
    {:noreply, assign(socket, :selected, new_selected)}
  end

  def handle_event("move-selected", %{"url" => url, "dir" => dir}, socket) do
    new_selected = move(socket.assigns.selected, url, dir)
    notify_parent(socket, new_selected)
    {:noreply, assign(socket, :selected, new_selected)}
  end

  def handle_event("cancel-entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  def handle_event("delete-asset", %{"id" => id}, socket) do
    case Media.get_asset(id, socket_opts(socket.assigns)) do
      {:ok, asset} ->
        Media.delete_asset(asset, socket_opts(socket.assigns))

        new_selected = Enum.reject(socket.assigns.selected, &(&1 == asset.url))
        notify_parent(socket, new_selected)

        {:noreply,
         socket
         |> assign(:assets, Enum.reject(socket.assigns.assets, &(&1.id == id)))
         |> assign(:staged, Enum.reject(socket.assigns.staged, &(&1 == asset.url)))
         |> assign(:selected, new_selected)
         |> reload_folders()}

      _ ->
        {:noreply, socket}
    end
  end

  # ── Upload progress (auto-upload consumes as soon as an entry finishes) ──

  def handle_progress(:media, entry, socket) do
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
                   socket_opts(socket.assigns)
                 ) do
            {:ok, {:ok, asset}}
          else
            {:error, reason} -> {:ok, {:error, reason}}
          end
        end)

      case result do
        {:ok, asset} ->
          staged =
            add_selected(
              socket.assigns.staged,
              asset.url,
              socket.assigns.multiple,
              socket.assigns.max_selected
            )

          {:noreply,
           socket
           |> assign(:assets, [asset | socket.assigns.assets])
           |> assign(:staged, staged)
           |> reload_folders()}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp socket_opts(assigns) do
    [
      tenant: assigns.tenant,
      actor: assigns[:current_user],
      context: %{store_id: assigns.store_id, tenant: assigns.tenant}
    ]
  end

  defp load_assets_page(opts, query, folder, page) do
    limit = 24
    offset = (page - 1) * limit
    opts = Keyword.put(opts, :page, offset: offset, count: true)
    Media.list_assets(opts, query, folder)
  end

  defp reload_assets(socket) do
    case load_assets_page(
           socket_opts(socket.assigns),
           socket.assigns.query,
           socket.assigns.current_folder,
           socket.assigns.page
         ) do
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
    |> assign(:folders, Media.list_folders(socket_opts(socket.assigns)))
    |> assign(:counts, Media.folder_counts(socket_opts(socket.assigns)))
  end

  defp parse_folder("all"), do: :all
  defp parse_folder("unfiled"), do: :unfiled
  defp parse_folder(id), do: id

  defp real_folder_id(:all), do: nil
  defp real_folder_id(:unfiled), do: nil
  defp real_folder_id(id), do: id

  defp toggle_url(_staged, url, false, _max), do: [url]

  defp toggle_url(staged, url, true, max) do
    cond do
      url in staged -> Enum.reject(staged, &(&1 == url))
      is_integer(max) and length(staged) >= max -> staged
      true -> staged ++ [url]
    end
  end

  defp add_selected(_list, url, false, _max), do: [url]

  defp add_selected(list, url, true, max) do
    if is_integer(max) and length(list) >= max, do: list, else: list ++ [url]
  end

  defp move(list, url, dir) do
    idx = Enum.find_index(list, &(&1 == url))

    cond do
      is_nil(idx) -> list
      dir == "left" and idx > 0 -> swap(list, idx, idx - 1)
      dir == "right" and idx < length(list) - 1 -> swap(list, idx, idx + 1)
      true -> list
    end
  end

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)
    list |> List.replace_at(i, b) |> List.replace_at(j, a)
  end

  defp notify_parent(socket, selected) do
    send(self(), {:media_manager_updated, socket.assigns.id, selected})
  end

  defp hidden_name(field, name, multiple) do
    base = if field, do: field.name, else: name
    if multiple, do: base <> "[]", else: base
  end

  # Pushes `event` to this component and, when a wrapping `form` selector was
  # given (see the `:form` assign), also submits that form immediately so the
  # parent LiveView's staged state never drifts from what's shown here. Without
  # this, any unrelated parent re-render would reset `@selected` back to the
  # parent's last-saved snapshot (via the `assign(socket, assigns)` in
  # `update/2`), silently discarding picks the user hasn't explicitly saved.
  defp submit_js(myself, form, event, opts \\ []) do
    js = JS.push(event, Keyword.put(opts, :target, myself))
    if form, do: JS.dispatch(js, "submit", to: form), else: js
  end

  defp upload_error_message(:too_large), do: "File is too large (max 10MB)"
  defp upload_error_message(:too_many_files), do: "Too many files selected at once"
  defp upload_error_message(:not_accepted), do: "That file type isn't supported"
  defp upload_error_message(err), do: to_string(err)

  # ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-2">
      <div :if={@label} class="flex items-center justify-between">
        <span class="text-sm font-medium text-base-content">{@label}</span>
        <span :if={@max_selected} class="text-xs text-base-content/40">
          {length(@selected)}/{@max_selected}
        </span>
      </div>

      <div class="grid grid-cols-3 gap-3 sm:grid-cols-4 md:grid-cols-6">
        <div
          :for={{url, index} <- Enum.with_index(@selected)}
          class="group relative aspect-square overflow-hidden rounded-lg border border-base-300 bg-base-200"
        >
          <img src={url} class="h-full w-full object-cover" loading="lazy" />
          <div class="absolute inset-0 flex items-start justify-between bg-black/0 p-1 opacity-0 transition-opacity group-hover:bg-black/10 group-hover:opacity-100">
            <div :if={@multiple and length(@selected) > 1} class="flex gap-0.5">
              <button
                :if={index > 0}
                type="button"
                phx-click={
                  submit_js(@myself, @form, "move-selected", value: %{url: url, dir: "left"})
                }
                class="flex size-6 items-center justify-center rounded-md bg-base-100/90 text-base-content/70 shadow hover:text-base-content"
              >
                <.icon name="hero-chevron-left" class="size-3.5" />
              </button>
              <button
                :if={index < length(@selected) - 1}
                type="button"
                phx-click={
                  submit_js(@myself, @form, "move-selected", value: %{url: url, dir: "right"})
                }
                class="flex size-6 items-center justify-center rounded-md bg-base-100/90 text-base-content/70 shadow hover:text-base-content"
              >
                <.icon name="hero-chevron-right" class="size-3.5" />
              </button>
            </div>
            <button
              type="button"
              phx-click={submit_js(@myself, @form, "remove-selected", value: %{url: url})}
              class="ml-auto flex size-6 items-center justify-center rounded-md bg-base-100/90 text-error shadow hover:bg-error hover:text-error-content"
              title="Remove"
            >
              <.icon name="hero-x-mark" class="size-3.5" />
            </button>
          </div>
          <span
            :if={index == 0 and @multiple and length(@selected) > 1}
            class="absolute bottom-1 left-1 rounded bg-base-100/90 px-1.5 py-0.5 text-[10px] font-medium text-base-content/70"
          >
            Cover
          </span>
        </div>

        <button
          :if={is_nil(@max_selected) or length(@selected) < @max_selected}
          type="button"
          phx-click="open-modal"
          phx-target={@myself}
          class="flex aspect-square flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-base-300 text-base-content/40 transition-colors hover:border-primary/50 hover:text-primary"
        >
          <.icon name="hero-photo" class="size-6" />
          <span class="text-xs font-medium">Add media</span>
        </button>
      </div>

      <p :if={@helper} class="text-xs text-base-content/40">{@helper}</p>

      <input
        :for={url <- @selected}
        type="hidden"
        name={hidden_name(@field, @name, @multiple)}
        value={url}
      />
      <input
        :if={not @multiple and @selected == []}
        type="hidden"
        name={hidden_name(@field, @name, false)}
        value=""
      />

      <div
        :if={@show_modal}
        class="fixed inset-0 z-[100] flex items-center justify-center p-4"
        phx-window-keydown="close-modal"
        phx-key="Escape"
        phx-target={@myself}
      >
        <div class="absolute inset-0 bg-black/50" phx-click="close-modal" phx-target={@myself} />
        <div class="relative flex h-[85vh] w-full max-w-5xl flex-col overflow-hidden rounded-2xl bg-base-100 shadow-2xl">
          <div class="flex items-center justify-between border-b border-base-200 px-5 py-4">
            <div class="flex items-center gap-1 rounded-lg bg-base-200 p-1">
              <button
                type="button"
                phx-click="set-tab"
                phx-value-tab="library"
                phx-target={@myself}
                class={[
                  "rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                  @tab == "library" && "bg-base-100 shadow-sm",
                  @tab != "library" && "text-base-content/60"
                ]}
              >
                Library
              </button>
              <button
                type="button"
                phx-click="set-tab"
                phx-value-tab="upload"
                phx-target={@myself}
                class={[
                  "rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                  @tab == "upload" && "bg-base-100 shadow-sm",
                  @tab != "upload" && "text-base-content/60"
                ]}
              >
                Upload
              </button>
            </div>
            <button
              type="button"
              phx-click="close-modal"
              phx-target={@myself}
              class="flex size-8 items-center justify-center rounded-lg text-base-content/50 hover:bg-base-200"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-5">
            <div :if={@tab == "upload"}>
              <p
                :if={@current_folder not in [:all, :unfiled]}
                class="mb-3 text-xs text-base-content/50"
              >
                Uploading into
                <span class="font-medium text-base-content">
                  {Enum.find(@folders, &(&1.id == @current_folder)) |> then(&(&1 && &1.name))}
                </span>
              </p>
              <form
                id={"#{@id}-upload-form"}
                phx-change="validate"
                phx-target={@myself}
                phx-drop-target={@uploads.media.ref}
              >
                <label class="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-base-300 bg-base-200/40 px-6 py-10 text-center transition-colors hover:border-primary/50 hover:bg-primary/5">
                  <.icon name="hero-arrow-up-tray" class="size-8 text-base-content/40" />
                  <span class="text-sm font-medium text-base-content">
                    Drop images here or click to browse
                  </span>
                  <span class="text-xs text-base-content/40">PNG, JPG, GIF, WEBP, SVG up to 10MB</span>
                  <.live_file_input upload={@uploads.media} class="hidden" />
                </label>
              </form>

              <p
                :for={err <- upload_errors(@uploads.media)}
                class="mt-2 flex items-center gap-1.5 text-sm text-error"
              >
                <.icon name="hero-exclamation-circle" class="size-4" />{upload_error_message(err)}
              </p>

              <div :if={@uploads.media.entries != []} class="mt-4 space-y-2">
                <div
                  :for={entry <- @uploads.media.entries}
                  class="flex items-center gap-3 rounded-lg border border-base-200 p-2"
                >
                  <.live_img_preview entry={entry} class="size-10 shrink-0 rounded object-cover" />
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-medium">{entry.client_name}</p>
                    <div class="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-base-200">
                      <div
                        class="h-full rounded-full bg-primary transition-all"
                        style={"width: #{entry.progress}%"}
                      />
                    </div>
                    <p
                      :for={err <- upload_errors(@uploads.media, entry)}
                      class="mt-1 text-xs text-error"
                    >
                      {upload_error_message(err)}
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="cancel-entry"
                    phx-value-ref={entry.ref}
                    phx-target={@myself}
                    class="flex size-7 shrink-0 items-center justify-center rounded-md text-base-content/40 hover:bg-base-200 hover:text-error"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
            </div>

            <div :if={@tab == "library"} class="flex h-full gap-5">
              <div class="w-44 shrink-0 border-r border-base-200 pr-4">
                <.folder_nav
                  folders={@folders}
                  counts={@counts}
                  current={@current_folder}
                  target={@myself}
                  creating={@creating_folder}
                  editing_id={@editing_folder_id}
                />
              </div>

              <div class="min-w-0 flex-1">
                <div class="relative mb-4">
                  <.icon
                    name="hero-magnifying-glass"
                    class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-base-content/30"
                  />
                  <input
                    type="text"
                    value={@query}
                    phx-keyup="search"
                    phx-debounce="300"
                    phx-target={@myself}
                    placeholder="Search media…"
                    class="input w-full pl-9"
                  />
                </div>

                <div
                  :if={@assets == []}
                  class="flex flex-col items-center justify-center py-16 text-center"
                >
                  <.icon name="hero-photo" class="size-10 text-base-content/20" />
                  <p class="mt-3 text-sm font-medium text-base-content/60">No media yet</p>
                  <p class="text-xs text-base-content/40">
                    Upload images from the Upload tab to build your library.
                  </p>
                </div>

                <div :if={@assets != []} class="grid grid-cols-3 gap-3 sm:grid-cols-4 md:grid-cols-5">
                  <div
                    :for={asset <- @assets}
                    class="group relative aspect-square overflow-hidden rounded-lg border border-base-300 bg-base-200"
                  >
                    <button
                      type="button"
                      phx-click="toggle-asset"
                      phx-value-url={asset.url}
                      phx-target={@myself}
                      class="absolute inset-0"
                    >
                      <img src={asset.url} class="h-full w-full object-cover" loading="lazy" />
                    </button>
                    <div class={[
                      "pointer-events-none absolute inset-0 border-2 transition-colors",
                      asset.url in @staged && "border-primary bg-primary/10",
                      asset.url not in @staged && "border-transparent"
                    ]} />
                    <div
                      :if={asset.url in @staged}
                      class="absolute right-1.5 top-1.5 flex size-5 items-center justify-center rounded-full bg-primary text-primary-content"
                    >
                      <.icon name="hero-check" class="size-3.5" />
                    </div>
                    <button
                      type="button"
                      phx-click="delete-asset"
                      phx-value-id={asset.id}
                      phx-target={@myself}
                      data-confirm="Delete this file permanently?"
                      class="absolute bottom-1.5 right-1.5 flex size-6 items-center justify-center rounded-md bg-base-100/90 text-base-content/50 opacity-0 shadow transition-opacity group-hover:opacity-100 hover:text-error"
                      title="Delete"
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </div>
                </div>

                <.pagination
                  page={@assets_page}
                  phx_click="set-page"
                  phx_target={@myself}
                  class="mt-4"
                />
              </div>
            </div>
          </div>

          <div class="flex items-center justify-between border-t border-base-200 px-5 py-4">
            <span class="text-sm text-base-content/50">
              {length(@staged)} selected{if @max_selected, do: " / #{@max_selected}", else: ""}
            </span>
            <div class="flex items-center gap-2">
              <.ui_button type="button" variant="ghost" phx-click="close-modal" phx-target={@myself}>
                Cancel
              </.ui_button>
              <.ui_button
                type="button"
                variant="primary"
                phx-click={submit_js(@myself, @form, "confirm-selection")}
              >
                Use selected
              </.ui_button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
