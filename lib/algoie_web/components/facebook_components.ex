defmodule AlgoieWeb.FacebookComponents do
  use AlgoieWeb, :html

  attr :active, :atom, required: true
  attr :account, :any, default: nil
  attr :store_name, :string, required: true
  attr :current_user, :any, required: true
  attr :collapsed, :boolean, default: false
  attr :page, :map, default: nil
  slot :inner_block, required: true

  def facebook_shell(assigns) do
    assigns = assign(assigns, :nav_items, nav_items())

    ~H"""
    <div class="min-h-screen bg-white text-slate-950 lg:flex">
      <aside class={[
        "sticky top-0 hidden h-screen shrink-0 flex-col border-r border-slate-200 bg-[#fafafa] text-slate-700 transition-[width] duration-200 lg:flex",
        if(@collapsed, do: "w-16", else: "w-56")
      ]}>
        <div class="flex h-16 items-center gap-3 border-b border-slate-200 px-4">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-[#0866ff] text-white">
            <.icon name="hero-chat-bubble-bottom-center-text" class="size-5" />
          </span>
          <div :if={!@collapsed}>
            <p class="text-sm font-bold leading-none text-slate-900">Facebook Studio</p>
            <p class="mt-1 text-[11px] text-slate-400">{@store_name}</p>
          </div>
        </div>

        <nav
          id="facebook-sidebar"
          class={[
            "flex-1 overflow-y-auto py-6",
            if(@collapsed, do: "px-2", else: "px-4")
          ]}
        >
          <p
            :if={!@collapsed}
            class="px-3 text-[10px] font-bold uppercase tracking-[0.16em] text-slate-400"
          >
            Workspace
          </p>
          <div class="mt-3 space-y-1">
            <.link
              :for={{key, label, icon, path} <- @nav_items}
              id={"facebook-nav-#{key}"}
              navigate={path}
              class={[
                "flex items-center rounded-md px-3 py-2.5 text-sm transition",
                if(@collapsed, do: "justify-center", else: "gap-3"),
                @active == key &&
                  "bg-slate-200/80 font-semibold text-slate-950",
                @active != key &&
                  "font-medium text-slate-500 hover:bg-slate-100 hover:text-slate-900"
              ]}
            >
              <.icon name={icon} class="size-5 shrink-0" /> <span :if={!@collapsed}>{label}</span>
            </.link>
          </div>
        </nav>

        <div class="border-t border-slate-200 p-2">
          <button
            id="facebook-sidebar-toggle"
            type="button"
            phx-click="toggle-facebook-sidebar"
            title={if(@collapsed, do: "Expand sidebar", else: "Collapse sidebar")}
            class="mb-1 flex w-full items-center justify-center rounded-md px-3 py-2.5 text-slate-400 transition hover:bg-slate-100 hover:text-slate-900"
          >
            <.icon
              name={if(@collapsed, do: "hero-chevron-double-right", else: "hero-chevron-double-left")}
              class="size-4"
            />
          </button>
          <.link
            id="back-to-dashboard"
            navigate={~p"/dashboard"}
            class={[
              "group flex w-full items-center rounded-md px-3 py-2.5 text-sm font-medium text-slate-500 transition hover:bg-slate-100 hover:text-slate-900",
              if(@collapsed, do: "justify-center", else: "gap-3")
            ]}
          >
            <.icon name="hero-arrow-left" class="size-4 transition group-hover:-translate-x-0.5" />
            <span :if={!@collapsed}>Back to Algoie</span>
          </.link>
        </div>
      </aside>

      <div class="min-w-0 flex-1">
        <header class="sticky top-0 z-30 border-b border-slate-200 bg-white/95 backdrop-blur-xl">
          <div class="flex h-16 items-center gap-4 px-4 sm:px-6 lg:px-6">
            <.link
              navigate={~p"/dashboard"}
              class="inline-flex size-10 items-center justify-center rounded-xl text-slate-500 transition hover:bg-slate-100 hover:text-slate-900 lg:hidden"
              aria-label="Back to Algoie"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <div>
              <p class="text-sm font-bold text-slate-900">
                {if(@page, do: @page["name"], else: "Facebook Studio")}
              </p>
              <p class="mt-0.5 text-xs text-slate-400">
                {if(@page && @page["username"], do: "@#{@page["username"]}", else: @store_name)}
              </p>
            </div>
            <div class="ml-auto flex items-center gap-3">
              <span class={[
                "hidden items-center gap-2 rounded-full px-3 py-1.5 text-xs font-bold sm:inline-flex",
                if(@account,
                  do: "bg-emerald-50 text-emerald-700",
                  else: "bg-amber-50 text-amber-700"
                )
              ]}>
                <span class={[
                  "size-2 rounded-full",
                  if(@account, do: "bg-emerald-500", else: "bg-amber-500")
                ]}></span>
                {if(@account, do: "Page connected", else: "Not connected")}
              </span>
              <span class="flex size-9 items-center justify-center rounded-full bg-slate-900 text-xs font-bold text-white">
                {@current_user.email |> to_string() |> String.first() |> String.upcase()}
              </span>
            </div>
          </div>
          <nav class="flex gap-1 overflow-x-auto border-t border-slate-100 px-4 py-2 lg:hidden">
            <.link
              :for={{key, label, _icon, path} <- @nav_items}
              navigate={path}
              class={[
                "shrink-0 rounded-lg px-3 py-2 text-xs font-bold",
                if(@active == key,
                  do: "bg-[#0866ff] text-white",
                  else: "text-slate-500 hover:bg-slate-100"
                )
              ]}
            >
              {label}
            </.link>
          </nav>
        </header>

        <main class="px-4 py-6 sm:px-6 lg:px-6">
          <div class="mx-auto max-w-[90rem]">{render_slot(@inner_block)}</div>
        </main>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, default: "hero-squares-2x2"
  slot :actions

  def facebook_header(assigns) do
    ~H"""
    <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h2 class="text-xl font-bold tracking-tight text-slate-950">{@title}</h2>
        <p class="mt-1 max-w-2xl text-sm leading-5 text-slate-500">{@description}</p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :title, :string, default: "Connect Facebook first"

  def facebook_disconnected(assigns) do
    ~H"""
    <div class="rounded-3xl border border-slate-200 bg-white p-10 text-center shadow-sm">
      <span class="mx-auto flex size-14 items-center justify-center rounded-2xl bg-blue-500/10 text-[#0866ff]">
        <.icon name="hero-link" class="size-7" />
      </span>
      <h2 class="mt-4 text-xl font-bold">{@title}</h2>
      <p class="mx-auto mt-2 max-w-md text-sm text-slate-500">
        Connect a Facebook Page to use this part of Facebook Studio.
      </p>
      <.link
        navigate={~p"/dashboard/social"}
        class="mt-6 inline-flex items-center gap-2 rounded-xl bg-[#0866ff] px-5 py-3 text-sm font-bold text-white transition hover:bg-blue-700"
      >
        Manage social accounts <.icon name="hero-arrow-right" class="size-4" />
      </.link>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true

  def metric_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
      <div class="flex items-center justify-between">
        <p class="text-xs font-bold uppercase tracking-wider text-slate-400">{@label}</p><.icon
          name={@icon}
          class="size-5 text-[#0866ff]"
        />
      </div>
      <p class="mt-3 truncate text-lg font-bold text-slate-950">{@value}</p>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :icon, :string, required: true

  def quick_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="group rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-blue-200 hover:shadow-md"
    >
      <span class="flex size-10 items-center justify-center rounded-xl bg-blue-50 text-[#0866ff]"><.icon
        name={@icon}
        class="size-5"
      /></span>
      <h3 class="mt-4 font-bold">{@title}</h3><p class="mt-1 text-sm leading-6 text-slate-500">
        {@text}
      </p>
    </.link>
    """
  end

  attr :title, :string, required: true

  def locked_panel(assigns) do
    ~H"""
    <div class="rounded-3xl border border-amber-200 bg-amber-50 p-10 text-center">
      <.icon name="hero-lock-closed" class="mx-auto size-8 text-amber-600" /><h3 class="mt-4 text-xl font-bold text-amber-950">
        {@title}
      </h3><p class="mx-auto mt-2 max-w-lg text-sm text-amber-800">
        This workspace is ready. Upgrade the provider plan to unlock live data and actions.
      </p>
    </div>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider",
      @status in ["published", "success"] && "bg-emerald-50 text-emerald-700",
      @status in ["scheduled", "pending"] && "bg-blue-50 text-blue-700",
      @status == "publishing" && "bg-violet-50 text-violet-700",
      @status == "partial" && "bg-amber-50 text-amber-700",
      @status in ["failed", "error"] && "bg-red-50 text-red-700",
      @status in ["draft", "cancelled", "unknown"] && "bg-slate-100 text-slate-600"
    ]}>{@status}</span>
    """
  end

  defp nav_items do
    [
      {:overview, "Overview", "hero-squares-2x2", ~p"/dashboard/facebook"},
      {:publishing, "Create", "hero-pencil-square", ~p"/dashboard/facebook/publishing"},
      {:posts, "Posts & Calendar", "hero-calendar-days", ~p"/dashboard/facebook/posts"},
      {:analytics, "Analytics", "hero-chart-bar-square", ~p"/dashboard/facebook/analytics"},
      {:messages, "Messages", "hero-inbox", ~p"/dashboard/facebook/inbox"},
      {:comments, "Comments", "hero-chat-bubble-left",
       ~p"/dashboard/facebook/inbox?tab=comments"},
      {:automations, "Automations", "hero-bolt", ~p"/dashboard/facebook/automations"}
    ]
  end
end
