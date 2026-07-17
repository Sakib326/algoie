defmodule AlgoieWeb.Components.MediaFolderNav do
  @moduledoc """
  Shared WordPress-style folder sidebar used by both the standalone Media
  Library page (`AlgoieWeb.MediaLive.Index`) and the embeddable
  `AlgoieWeb.Components.MediaManagerComponent` picker.

  Pure rendering — the owning LiveView/LiveComponent keeps the actual state
  (folders, counts, current selection) and implements a small, shared set of
  event names:

    * `"select-folder"` — value `id` is `"all"`, `"unfiled"`, or a folder id
    * `"new-folder-start"` / `"new-folder-cancel"`
    * `"new-folder-save"` — form submit with a `"name"` param
    * `"rename-folder-start"` / `"rename-folder-cancel"` — value `id`
    * `"rename-folder-save"` — form submit with `"id"` and `"name"` params
    * `"delete-folder"` — value `id`
  """

  use Phoenix.Component
  import AlgoieWeb.CoreComponents

  attr :folders, :list, required: true, doc: "list of %{id:, name:}"
  attr :counts, :map, required: true, doc: "%{all:, unfiled:, folders: %{id => count}}"
  attr :current, :any, required: true, doc: ":all | :unfiled | folder id"
  attr :target, :any, default: nil
  attr :creating, :boolean, default: false
  attr :editing_id, :any, default: nil
  attr :class, :any, default: nil

  def folder_nav(assigns) do
    ~H"""
    <nav class={["space-y-0.5", @class]}>
      <button
        type="button"
        phx-click="select-folder"
        phx-value-id="all"
        phx-target={@target}
        class={[
          "flex w-full items-center justify-between rounded-lg px-3 py-2 text-sm font-medium transition-colors",
          @current == :all && "bg-primary/10 text-primary",
          @current != :all && "text-base-content/70 hover:bg-base-200"
        ]}
      >
        <span class="flex items-center gap-2">
          <.icon name="hero-photo" class="size-4" /> All media
        </span>
        <span class="text-xs text-base-content/40">{@counts.all}</span>
      </button>

      <button
        type="button"
        phx-click="select-folder"
        phx-value-id="unfiled"
        phx-target={@target}
        class={[
          "flex w-full items-center justify-between rounded-lg px-3 py-2 text-sm font-medium transition-colors",
          @current == :unfiled && "bg-primary/10 text-primary",
          @current != :unfiled && "text-base-content/70 hover:bg-base-200"
        ]}
      >
        <span class="flex items-center gap-2">
          <.icon name="hero-inbox" class="size-4" /> Unfiled
        </span>
        <span class="text-xs text-base-content/40">{@counts.unfiled}</span>
      </button>

      <div class="flex items-center justify-between px-3 pb-1 pt-3">
        <p class="text-[11px] font-semibold uppercase tracking-wider text-base-content/40">
          Folders
        </p>
        <button
          type="button"
          phx-click="new-folder-start"
          phx-target={@target}
          class="flex size-5 items-center justify-center rounded text-base-content/40 hover:bg-base-200 hover:text-base-content"
          title="New folder"
        >
          <.icon name="hero-plus" class="size-3.5" />
        </button>
      </div>

      <form
        :if={@creating}
        phx-submit="new-folder-save"
        phx-target={@target}
        class="flex items-center gap-1 px-1 pb-1"
      >
        <input
          type="text"
          name="name"
          autofocus
          placeholder="Folder name"
          class="input input-sm w-full"
        />
        <button
          type="submit"
          class="flex size-7 items-center justify-center rounded-md text-success hover:bg-success/10"
        >
          <.icon name="hero-check" class="size-4" />
        </button>
        <button
          type="button"
          phx-click="new-folder-cancel"
          phx-target={@target}
          class="flex size-7 items-center justify-center rounded-md text-base-content/40 hover:bg-base-200"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </form>

      <p :if={@folders == [] and not @creating} class="px-3 py-1 text-xs text-base-content/40">
        No folders yet.
      </p>

      <div :for={folder <- @folders} class="group">
        <form
          :if={@editing_id == folder.id}
          phx-submit="rename-folder-save"
          phx-value-id={folder.id}
          phx-target={@target}
          class="flex items-center gap-1 px-1 pb-1"
        >
          <input
            type="text"
            name="name"
            value={folder.name}
            autofocus
            class="input input-sm w-full"
          />
          <button
            type="submit"
            class="flex size-7 items-center justify-center rounded-md text-success hover:bg-success/10"
          >
            <.icon name="hero-check" class="size-4" />
          </button>
          <button
            type="button"
            phx-click="rename-folder-cancel"
            phx-target={@target}
            class="flex size-7 items-center justify-center rounded-md text-base-content/40 hover:bg-base-200"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </form>

        <div
          :if={@editing_id != folder.id}
          class={[
            "flex items-center justify-between rounded-lg px-1 py-0.5 pl-2 transition-colors",
            @current == folder.id && "bg-primary/10",
            @current != folder.id && "hover:bg-base-200"
          ]}
        >
          <button
            type="button"
            phx-click="select-folder"
            phx-value-id={folder.id}
            phx-target={@target}
            class={[
              "flex min-w-0 flex-1 items-center gap-2 py-1.5 text-left text-sm font-medium truncate",
              @current == folder.id && "text-primary",
              @current != folder.id && "text-base-content/70"
            ]}
          >
            <.icon name="hero-folder" class="size-4 shrink-0" />
            <span class="truncate">{folder.name}</span>
          </button>
          <span class="text-xs text-base-content/40 shrink-0">
            {Map.get(@counts.folders, folder.id, 0)}
          </span>
          <div class="flex shrink-0 items-center opacity-0 group-hover:opacity-100">
            <button
              type="button"
              phx-click="rename-folder-start"
              phx-value-id={folder.id}
              phx-target={@target}
              class="flex size-6 items-center justify-center rounded text-base-content/40 hover:bg-base-200 hover:text-base-content"
              title="Rename"
            >
              <.icon name="hero-pencil" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click="delete-folder"
              phx-value-id={folder.id}
              phx-target={@target}
              data-confirm="Delete this folder? Files inside will move to Unfiled."
              class="flex size-6 items-center justify-center rounded text-base-content/40 hover:bg-error/10 hover:text-error"
              title="Delete"
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
          </div>
        </div>
      </div>
    </nav>
    """
  end
end
