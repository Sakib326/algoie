defmodule AlgoieWeb.Layouts do
  @moduledoc """
  Layouts for the application.
  """
  use AlgoieWeb, :html

  # ── Root layout (HTML skeleton) ──
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title default="Algoie" suffix="" phx-no-format>{assigns[:page_title]}</.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
        <script>
          (() => {
            const systemTheme = () => matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
            const setTheme = (theme) => {
              if (theme === "system") {
                localStorage.removeItem("phx:theme");
                document.documentElement.setAttribute("data-theme", systemTheme());
                document.documentElement.setAttribute("data-theme-source", "system");
              } else {
                localStorage.setItem("phx:theme", theme);
                document.documentElement.setAttribute("data-theme", theme);
                document.documentElement.setAttribute("data-theme-source", "user");
              }
            };
            if (!document.documentElement.hasAttribute("data-theme")) {
              setTheme(localStorage.getItem("phx:theme") || "system");
            }
            window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"));
            document.addEventListener("click", (e) => {
              const btn = e.target.closest("button[data-phx-theme]");
              if (btn) setTheme(btn.dataset.phxTheme);
            });
            matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
              if (document.documentElement.getAttribute("data-theme-source") === "system") {
                document.documentElement.setAttribute("data-theme", systemTheme());
              }
            });
          })();
        </script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end

  # ── Public layout ──
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_user, :any, default: nil
  attr :wide, :boolean, default: false
  attr :shell, :string, default: "public", values: ~w(public bare)
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      :if={@shell == "public"}
      class="navbar bg-base-100 border-b border-base-200 px-4 sm:px-6 lg:px-8"
    >
      <div class="flex-1">
        <.link navigate="/" class="flex items-center gap-2">
          <.icon name="hero-shopping-bag" class="size-8 text-primary" />
          <span class="text-lg font-bold">Algoie</span>
        </.link>
      </div>
      <div class="flex-none">
        <ul class="menu menu-horizontal gap-1 items-center">
          <li><.link navigate="/">Home</.link></li>
          <li><.link navigate="/sign-in">Sign In</.link></li>
          <li><.link navigate="/register" class="btn btn-primary btn-sm">Register</.link></li>
          <li><.theme_toggle /></li>
        </ul>
      </div>
    </header>
    <main :if={@shell == "public"} class="px-4 py-8 sm:px-6 lg:px-8">
      <div class={"mx-auto space-y-4 #{if @wide, do: "max-w-5xl", else: "max-w-2xl"}"}>
        {render_slot(@inner_block)}
      </div>
    </main>
    <div :if={@shell == "bare"}>{render_slot(@inner_block)}</div>
    <footer :if={@shell == "public"} class="footer footer-center p-4 bg-base-200 text-base-content">
      <div>
        <p>Algoie — Multi-tenant ecommerce platform</p>
      </div>
    </footer>
    <.flash_group flash={@flash} />
    """
  end

  # ── Dashboard layout ──
  attr :flash, :map, required: true
  attr :current_user, :any, required: true
  attr :tenant, :string, default: nil
  attr :store_id, :string, default: nil
  attr :store_name, :string, default: "Store"
  attr :user_stores, :list, default: []
  attr :page_title, :string, default: "Dashboard"
  attr :active, :atom, default: nil
  attr :full_bleed, :boolean, default: false
  slot :inner_block, required: true

  def dashboard(assigns) do
    current_store = Enum.find(assigns.user_stores, &(&1.store_id == to_string(assigns.store_id)))
    permissions = if current_store, do: current_store.permissions, else: []
    tenant_portal? = current_store && is_binary(current_store[:tenant_slug])

    assigns =
      assigns
      |> assign(:store_permissions, permissions)
      |> assign(:tenant_portal?, tenant_portal?)
      |> assign(:store_selector_url, store_selector_url(current_store))

    ~H"""
    <div class="min-h-screen bg-base-200/40">
      <input type="checkbox" id="nav-toggle" class="peer sr-only" />

      <aside class="fixed inset-y-0 left-0 z-50 flex w-64 -translate-x-full flex-col border-r border-base-300 bg-base-100 transition-transform duration-200 peer-checked:translate-x-0 lg:translate-x-0">
        <div class="flex h-16 items-center gap-2 px-5 border-b border-base-200">
          <.link navigate="/dashboard" class="flex items-center gap-2">
            <span class="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-content">
              <.icon name="hero-shopping-bag" class="size-5" />
            </span>
            <span class="text-lg font-bold tracking-tight">Algoie</span>
          </.link>
        </div>

        <%!-- Store switcher --%>
        <div class="px-3 py-3 border-b border-base-200">
          <.link
            :if={length(@user_stores) > 1 || @tenant_portal?}
            href={@store_selector_url}
            class="group flex items-center gap-3 rounded-lg p-2 hover:bg-base-200 transition-colors"
          >
            <span class="flex size-9 items-center justify-center rounded-lg bg-secondary/15 text-secondary text-sm font-semibold">
              {String.first(to_string(@store_name || "S")) |> String.upcase()}
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-[11px] uppercase tracking-wider text-base-content/40">
                {if @tenant_portal?, do: "Tenant control center", else: "Switch store"}
              </span>
              <span class="block text-sm font-medium truncate">{@store_name}</span>
            </span>
            <.icon name="hero-chevron-up-down" class="size-4 text-base-content/40" />
          </.link>
          <div
            :if={length(@user_stores) <= 1 && !@tenant_portal?}
            class="flex items-center gap-3 p-2"
          >
            <span class="flex size-9 items-center justify-center rounded-lg bg-secondary/15 text-secondary text-sm font-semibold">
              {String.first(to_string(@store_name || "S")) |> String.upcase()}
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-[11px] uppercase tracking-wider text-base-content/40">Store</span>
              <span class="block text-sm font-medium truncate">{@store_name}</span>
            </span>
          </div>
        </div>

        <nav class="flex-1 space-y-6 overflow-y-auto px-3 py-4">
          <div class="space-y-1">
            <.nav_item
              navigate="/dashboard"
              icon="hero-home"
              label="Overview"
              active={@active == :overview}
            />
          </div>
          <div class="space-y-1">
            <p class="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-base-content/40">
              Catalog
            </p>
            <.nav_item
              :if={allowed?(@store_permissions, "catalog.view")}
              navigate="/dashboard/products"
              icon="hero-cube"
              label="Products"
              active={@active == :products}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "catalog.view")}
              navigate="/dashboard/categories"
              icon="hero-folder"
              label="Categories"
              active={@active == :categories}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "catalog.view")}
              navigate="/dashboard/brands"
              icon="hero-tag"
              label="Brands"
              active={@active == :brands}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "catalog.view")}
              navigate="/dashboard/media"
              icon="hero-photo"
              label="Media Library"
              active={@active == :media}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "inventory.view")}
              navigate="/dashboard/inventory"
              icon="hero-archive-box"
              label="Inventory"
              active={@active == :inventory}
            />
          </div>
          <div class="space-y-1">
            <p class="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-base-content/40">
              Sales
            </p>
            <.nav_item
              :if={allowed?(@store_permissions, "orders.view")}
              navigate="/dashboard/orders"
              icon="hero-shopping-cart"
              label="Orders"
              active={@active == :orders}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "customers.view")}
              navigate="/dashboard/customers"
              icon="hero-users"
              label="Customers"
              active={@active == :customers}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "discounts.view")}
              navigate="/dashboard/coupons"
              icon="hero-ticket"
              label="Coupons"
              active={@active == :coupons}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "discounts.view")}
              navigate="/dashboard/delivery-charges"
              icon="hero-truck"
              label="Delivery Charges"
              active={@active == :delivery_charges}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "reports.view")}
              navigate="/dashboard/reports/sales"
              icon="hero-chart-bar-square"
              label="Sales Report"
              active={@active == :sales_report}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "reports.view")}
              navigate="/dashboard/reports/repeat-orders"
              icon="hero-arrow-path-rounded-square"
              label="Repeat Orders"
              active={@active == :repeat_orders}
            />
          </div>
          <div class="space-y-1">
            <p class="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-base-content/40">
              Engage
            </p>
            <.nav_item
              :if={allowed?(@store_permissions, "engagement.view")}
              navigate="/dashboard/conversations"
              icon="hero-chat-bubble-left-right"
              label="Conversations"
              active={@active == :conversations}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "engagement.view")}
              navigate="/dashboard/campaigns"
              icon="hero-megaphone"
              label="Ad Campaigns"
              active={@active == :campaigns}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "ai.use")}
              navigate="/dashboard/assistant"
              icon="hero-sparkles"
              label="AI Assistant"
              active={@active == :assistant}
            />
          </div>
          <div class="space-y-1">
            <p class="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-base-content/40">
              Configuration
            </p>
            <.nav_item
              :if={
                allowed?(@store_permissions, "social.view") or
                  allowed?(@store_permissions, "settings.view")
              }
              navigate="/dashboard/social"
              icon="hero-share"
              label="Social Publishing"
              active={@active == :social}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "settings.view")}
              navigate="/dashboard/settings"
              icon="hero-cog-6-tooth"
              label="Store Settings"
              active={@active == :settings}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "settings.view")}
              navigate="/dashboard/settings/email"
              icon="hero-envelope"
              label="Email Settings"
              active={@active == :email_settings}
            />
            <.nav_item
              :if={allowed?(@store_permissions, "team.view")}
              navigate="/dashboard/team"
              icon="hero-user-group"
              label="Team & Roles"
              active={@active == :team}
            />
          </div>
        </nav>

        <div class="border-t border-base-200 p-3">
          <div class="flex items-center gap-3 rounded-lg p-2">
            <span class="flex size-9 items-center justify-center rounded-full bg-primary/10 text-primary text-sm font-semibold">
              {String.first(to_string(@current_user.email) || "?") |> String.upcase()}
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium truncate">{@current_user.name || @current_user.email}</p>
              <p class="text-xs text-base-content/40 truncate">{@current_user.email}</p>
            </div>
            <.link
              href="/sign-out"
              method="delete"
              class="flex size-8 items-center justify-center rounded-lg text-base-content/50 hover:bg-base-200 hover:text-error transition-colors"
              title="Sign out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
            </.link>
          </div>
        </div>
      </aside>

      <label
        for="nav-toggle"
        class="fixed inset-0 z-40 hidden bg-black/40 backdrop-blur-sm peer-checked:block lg:hidden"
        aria-label="Close sidebar"
      ></label>

      <div class="lg:pl-64">
        <header class="sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-base-300 bg-base-100/80 px-4 backdrop-blur sm:px-6">
          <label
            for="nav-toggle"
            class="flex size-9 cursor-pointer items-center justify-center rounded-lg text-base-content/70 hover:bg-base-200 lg:hidden"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </label>
          <span class="text-sm font-medium text-base-content/60 truncate">{@page_title}</span>
          <div class="ml-auto flex items-center gap-2">
            <.theme_toggle />
          </div>
        </header>

        <main class={if(@full_bleed, do: "p-0", else: "p-4 sm:p-6 lg:p-8")}>
          <div class={if(@full_bleed, do: "w-full", else: "mx-auto max-w-7xl")}>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp allowed?(permissions, permission), do: permission in permissions

  defp store_selector_url(current_store) do
    path =
      case current_store do
        %{tenant_slug: slug} when is_binary(slug) -> "/tenant/#{slug}/dashboard"
        _ -> "/store-select"
      end

    AlgoieWeb.PublicURL.apex(path)
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        @active && "bg-primary/10 text-primary",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  # ── Storefront layout ──
  attr :flash, :map, required: true
  attr :store, :any, default: nil
  attr :current_customer, :any, default: nil
  slot :inner_block, required: true

  def storefront(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100">
      <header class="navbar bg-base-100 border-b border-base-200 sticky top-0 z-30 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate="/" class="flex items-center gap-2">
            <%= if @store && @store.logo_url do %>
              <img src={@store.logo_url} alt={@store.name} class="size-9 rounded-xl object-cover" />
            <% else %>
              <.icon name="hero-shopping-bag" class="size-7 text-primary" />
            <% end %>
            <span class="text-xl font-bold">{if(@store, do: @store.name, else: "Store")}</span>
          </.link>
        </div>
        <div class="flex-none">
          <ul class="menu menu-horizontal gap-1 items-center">
            <li><.link navigate="/" class="text-sm">Home</.link></li>
            <li><.link navigate="/products" class="text-sm">Products</.link></li>
            <li :if={@current_customer}>
              <.link navigate="/account" class="text-sm">My account</.link>
            </li>
            <li :if={!@current_customer}>
              <.link navigate="/account/sign-in" class="text-sm">Sign in</.link>
            </li>
            <li :if={@current_customer}>
              <.link href="/account/sign-out" method="delete" class="text-sm">Sign out</.link>
            </li>
            <li>
              <.link navigate="/cart" class="btn btn-primary btn-sm">
                <.icon name="hero-shopping-cart" class="size-4" /> Cart
              </.link>
            </li>
          </ul>
        </div>
      </header>
      <main class="flex-1 px-4 sm:px-6 lg:px-8 py-8">
        <div class="max-w-7xl mx-auto">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </div>
      </main>
      <footer class="bg-base-200 border-t border-base-300">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-8">
            <div>
              <div class="flex items-center gap-2 mb-4">
                <.icon name="hero-shopping-bag" class="size-6 text-primary" />
                <span class="text-lg font-bold">{if(@store, do: @store.name, else: "Store")}</span>
              </div>
              <p class="text-sm text-base-content/60">
                {if(@store && @store.address,
                  do: @store.address,
                  else: "Your one-stop shop for quality products."
                )}
              </p>
            </div>
            <div>
              <h3 class="font-semibold mb-3">Quick Links</h3>
              <ul class="space-y-2 text-sm">
                <li><.link navigate="/" class="link link-hover text-base-content/60">Home</.link></li>
                <li>
                  <.link navigate="/products" class="link link-hover text-base-content/60">Products</.link>
                </li>
                <li>
                  <.link navigate="/cart" class="link link-hover text-base-content/60">Cart</.link>
                </li>
                <li>
                  <.link navigate="/account" class="link link-hover text-base-content/60">My account</.link>
                </li>
              </ul>
            </div>
            <div>
              <h3 class="font-semibold mb-3">Support</h3>
              <ul class="space-y-2 text-sm">
                <li :if={@store && @store.phone}>
                  <a href={"tel:#{@store.phone}"} class="link link-hover text-base-content/60">{@store.phone}</a>
                </li>
                <li :if={@store && @store.email}>
                  <a href={"mailto:#{@store.email}"} class="link link-hover text-base-content/60">{@store.email}</a>
                </li>
                <li :if={!@store || (!@store.phone && !@store.email)}>
                  <span class="text-base-content/60">Contact us anytime</span>
                </li>
              </ul>
            </div>
          </div>
          <div class="border-t border-base-300 mt-8 pt-8 text-center text-sm text-base-content/40">
            <p>
              &copy; {DateTime.utc_now().year} {if(@store, do: @store.name, else: "Store")}. Powered by Algoie.
            </p>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  # ── Flash group ──
  def flash_group(assigns) do
    ~H"""
    <div
      id={assigns[:id] || "flash-group"}
      class="toast toast-top toast-end z-50 gap-3"
      aria-live="polite"
      aria-atomic="false"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  # ── Theme toggle ──
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />
      <button class="flex p-2 cursor-pointer w-1/3" data-phx-theme="system">
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-2 cursor-pointer w-1/3" data-phx-theme="light">
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-2 cursor-pointer w-1/3" data-phx-theme="dark">
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
