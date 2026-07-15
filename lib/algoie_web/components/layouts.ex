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
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar bg-base-100 border-b border-base-200 px-4 sm:px-6 lg:px-8">
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
    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class={"mx-auto space-y-4 #{if @wide, do: "max-w-5xl", else: "max-w-2xl"}"}>
        {render_slot(@inner_block)}
      </div>
    </main>
    <footer class="footer footer-center p-4 bg-base-200 text-base-content">
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
  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="dashboard-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-side z-40">
        <label for="dashboard-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 w-64 min-h-screen flex flex-col">
          <div class="px-4 py-4 border-b border-base-300">
            <.link navigate="/dashboard" class="flex items-center gap-2">
              <.icon name="hero-shopping-bag" class="size-8 text-primary" />
              <span class="text-lg font-bold">Algoie</span>
            </.link>
          </div>

          <%!-- Store Switcher --%>
          <%= if length(@user_stores) > 1 do %>
            <div class="px-4 py-3 border-b border-base-300" id="store-switcher">
              <.link
                navigate="/store-select"
                class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-300 transition group"
              >
                <div class="avatar placeholder">
                  <div class="bg-secondary text-secondary-content rounded-full w-8">
                    <span class="text-xs">
                      {String.first(@store_name || "?") |> String.upcase()}
                    </span>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-xs text-base-content/50">Switch store</p>
                  <p class="text-sm font-medium truncate">{@store_name}</p>
                </div>
                <.icon
                  name="hero-arrows-up-down"
                  class="size-4 text-base-content/30 group-hover:text-base-content/50"
                />
              </.link>
            </div>
          <% else %>
            <div class="px-4 py-3 border-b border-base-300">
              <div class="flex items-center gap-2 p-2">
                <div class="avatar placeholder">
                  <div class="bg-secondary text-secondary-content rounded-full w-8">
                    <span class="text-xs">
                      {String.first(@store_name || "?") |> String.upcase()}
                    </span>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium truncate">{@store_name}</p>
                </div>
              </div>
            </div>
          <% end %>

          <ul class="menu p-4 gap-1 flex-1">
            <li>
              <.link navigate="/dashboard"><.icon name="hero-home" class="size-5" /> Dashboard</.link>
            </li>
            <li>
              <.link navigate="/dashboard/products"><.icon name="hero-cube" class="size-5" /> Products</.link>
            </li>
            <li>
              <.link navigate="/dashboard/categories"><.icon name="hero-folder" class="size-5" />
              Categories</.link>
            </li>
            <li>
              <.link navigate="/dashboard/brands"><.icon name="hero-tag" class="size-5" /> Brands</.link>
            </li>
            <li>
              <.link navigate="/dashboard/orders"><.icon
                name="hero-clipboard-document-list"
                class="size-5"
              /> Orders</.link>
            </li>
            <li>
              <.link navigate="/dashboard/conversations"><.icon
                name="hero-chat-bubble-left-right"
                class="size-5"
              /> Conversations</.link>
            </li>
            <li>
              <.link navigate="/dashboard/campaigns"><.icon
                name="hero-megaphone"
                class="size-5"
              /> Ad Campaigns</.link>
            </li>
          </ul>

          <div class="border-t border-base-300 p-4">
            <div class="flex items-center gap-3">
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-full w-10">
                  <span class="text-sm">{String.first(@current_user.email || "?") |> String.upcase()}</span>
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium truncate">
                  {@current_user.name || @current_user.email}
                </p>
              </div>
              <.link href="/sign-out" method="delete" class="btn btn-ghost btn-sm btn-square">
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              </.link>
            </div>
          </div>
        </aside>
      </div>
      <div class="drawer-content flex flex-col">
        <div class="navbar bg-base-100 lg:hidden border-b border-base-200">
          <label for="dashboard-drawer" class="btn btn-ghost btn-square lg:hidden">
            <.icon name="hero-bars-3" class="size-5" />
          </label>
          <div class="flex-1">
            <span class="text-lg font-semibold">{assigns[:page_title] || "Dashboard"}</span>
          </div>
        </div>
        <main class="flex-1 p-6 lg:p-8">
          <div class="max-w-7xl mx-auto">
            <.flash_group flash={@flash} />
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>
    """
  end

  # ── Storefront layout ──
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def storefront(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100">
      <header class="navbar bg-base-100 border-b border-base-200 sticky top-0 z-30 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate="/" class="flex items-center gap-2">
            <.icon name="hero-shopping-bag" class="size-7 text-primary" />
            <span class="text-xl font-bold">Store</span>
          </.link>
        </div>
        <div class="flex-none">
          <ul class="menu menu-horizontal gap-1 items-center">
            <li><.link navigate="/" class="text-sm">Home</.link></li>
            <li><.link navigate="/products" class="text-sm">Products</.link></li>
            <li>
              <.link navigate="/products" class="btn btn-primary btn-sm">
                <.icon name="hero-shopping-bag" class="size-4" /> Shop
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
                <span class="text-lg font-bold">Store</span>
              </div>
              <p class="text-sm text-base-content/60">
                Your one-stop shop for quality products.
              </p>
            </div>
            <div>
              <h3 class="font-semibold mb-3">Quick Links</h3>
              <ul class="space-y-2 text-sm">
                <li><.link navigate="/" class="link link-hover text-base-content/60">Home</.link></li>
                <li>
                  <.link navigate="/products" class="link link-hover text-base-content/60">Products</.link>
                </li>
              </ul>
            </div>
            <div>
              <h3 class="font-semibold mb-3">Support</h3>
              <ul class="space-y-2 text-sm">
                <li><span class="text-base-content/60">Contact us anytime</span></li>
              </ul>
            </div>
          </div>
          <div class="border-t border-base-300 mt-8 pt-8 text-center text-sm text-base-content/40">
            <p>&copy; {DateTime.utc_now().year} Store. Powered by Algoie.</p>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  # ── Flash group ──
  def flash_group(assigns) do
    ~H"""
    <div id={assigns[:id] || "flash-group"} aria-live="polite">
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
