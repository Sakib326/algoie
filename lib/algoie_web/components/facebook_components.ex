defmodule AlgoieWeb.FacebookComponents do
  use AlgoieWeb, :html

  attr :active, :atom, required: true
  attr :account, :any, default: nil
  attr :store_name, :string, required: true
  attr :current_user, :any, required: true
  slot :inner_block, required: true

  def facebook_shell(assigns) do
    assigns = assign(assigns, :nav_items, nav_items())

    ~H"""
    <div class="min-h-screen bg-[#f4f7fc] text-slate-950 lg:flex">
      <aside class="hidden w-72 shrink-0 flex-col bg-[#111827] text-white lg:flex">
        <div class="flex h-20 items-center gap-3 border-b border-white/10 px-7">
          <span class="flex size-11 items-center justify-center rounded-2xl bg-[#0866ff] shadow-lg shadow-blue-500/25">
            <.icon name="hero-chat-bubble-bottom-center-text" class="size-6" />
          </span>
          <div>
            <p class="text-base font-bold leading-none">Facebook Studio</p>
            <p class="mt-1.5 text-xs text-slate-400">Powered by Algoie</p>
          </div>
        </div>

        <nav id="facebook-sidebar" class="flex-1 overflow-y-auto px-4 py-6">
          <p class="px-3 text-[10px] font-bold uppercase tracking-[0.2em] text-slate-500">
            Workspace
          </p>
          <div class="mt-3 space-y-1">
            <.link
              :for={{key, label, icon, path} <- @nav_items}
              id={"facebook-nav-#{key}"}
              navigate={path}
              class={[
                "flex items-center gap-3 rounded-xl px-3 py-3 text-sm transition",
                @active == key &&
                  "bg-[#0866ff] font-bold text-white shadow-lg shadow-blue-950/30",
                @active != key &&
                  "font-semibold text-slate-300 hover:bg-white/5 hover:text-white"
              ]}
            >
              <.icon name={icon} class="size-5" /> {label}
            </.link>
          </div>
        </nav>

        <div class="border-t border-white/10 p-4">
          <.link
            id="back-to-dashboard"
            navigate={~p"/dashboard"}
            class="group flex w-full items-center gap-3 rounded-xl px-3 py-3 text-sm font-semibold text-slate-300 transition hover:bg-white/5 hover:text-white"
          >
            <.icon name="hero-arrow-left" class="size-4 transition group-hover:-translate-x-0.5" />
            Back to Algoie
          </.link>
        </div>
      </aside>

      <div class="min-w-0 flex-1">
        <header class="sticky top-0 z-30 border-b border-slate-200/80 bg-white/90 backdrop-blur-xl">
          <div class="flex h-20 items-center gap-4 px-4 sm:px-6 lg:px-8">
            <.link
              navigate={~p"/dashboard"}
              class="inline-flex size-10 items-center justify-center rounded-xl text-slate-500 transition hover:bg-slate-100 hover:text-slate-900 lg:hidden"
              aria-label="Back to Algoie"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <div>
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-[#0866ff]">
                Facebook Studio
              </p>
              <h1 class="mt-1 text-xl font-bold tracking-tight">{@store_name}</h1>
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

        <main class="px-4 py-7 sm:px-6 lg:px-8 lg:py-10">
          <div class="mx-auto max-w-7xl">{render_slot(@inner_block)}</div>
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
    <div class="mb-7 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <div class="mb-3 flex size-11 items-center justify-center rounded-2xl bg-[#0866ff]/10 text-[#0866ff]">
          <.icon name={@icon} class="size-6" />
        </div>
        <h2 class="text-3xl font-bold tracking-tight text-slate-950">{@title}</h2>
        <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-500">{@description}</p>
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
      @status in ["failed", "error"] && "bg-red-50 text-red-700",
      @status in ["draft", "unknown"] && "bg-slate-100 text-slate-600"
    ]}>{@status}</span>
    """
  end

  defp nav_items do
    [
      {:overview, "Overview", "hero-squares-2x2", ~p"/dashboard/facebook"},
      {:publishing, "Create", "hero-pencil-square", ~p"/dashboard/facebook/publishing"},
      {:posts, "Posts & Calendar", "hero-calendar-days", ~p"/dashboard/facebook/posts"},
      {:analytics, "Analytics", "hero-chart-bar-square", ~p"/dashboard/facebook/analytics"},
      {:inbox, "Inbox", "hero-inbox", ~p"/dashboard/facebook/inbox"},
      {:engagement, "Comments & Reviews", "hero-chat-bubble-left-ellipsis",
       ~p"/dashboard/facebook/engagement"},
      {:automations, "Automations", "hero-bolt", ~p"/dashboard/facebook/automations"},
      {:settings, "Settings", "hero-cog-6-tooth", ~p"/dashboard/facebook/settings"}
    ]
  end
end
