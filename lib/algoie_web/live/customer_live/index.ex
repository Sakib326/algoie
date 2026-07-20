defmodule AlgoieWeb.CustomerLive.Index do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Customers.Customer
  alias Algoie.Orders.Order

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :customers)
     |> assign(:page_title, "Customers")
     |> assign(:search, "")
     |> assign(:page, 1)
     |> load_customers()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket |> assign(:search, String.trim(search)) |> assign(:page, 1) |> load_customers()}
  end

  def handle_event("page", %{"page" => page}, socket),
    do: {:noreply, socket |> assign(:page, parse_page(page)) |> load_customers()}

  defp load_customers(socket) do
    query = Customer |> Ash.Query.sort(inserted_at: :desc)

    query =
      if socket.assigns.search == "" do
        query
      else
        term = "%#{socket.assigns.search}%"
        Ash.Query.filter(query, ilike(name, ^term) or ilike(email, ^term) or ilike(phone, ^term))
      end

    opts = AlgoieWeb.Scope.opts(socket, page: false)

    all_customers =
      case Ash.read(query, opts) do
        {:ok, rows} -> rows
        _ -> []
      end

    page_size = 12
    page_count = max(ceil(length(all_customers) / page_size), 1)
    page = min(socket.assigns.page, page_count)
    customers = Enum.slice(all_customers, (page - 1) * page_size, page_size)

    customer_ids = Enum.map(customers, & &1.id)

    orders =
      if customer_ids == [] do
        []
      else
        case Order |> Ash.Query.filter(customer_id in ^customer_ids) |> Ash.read(opts) do
          {:ok, rows} -> rows
          _ -> []
        end
      end

    stats =
      orders
      |> Enum.group_by(& &1.customer_id)
      |> Map.new(fn {customer_id, records} ->
        total = Enum.reduce(records, Decimal.new(0), &Decimal.add(&1.total_amount, &2))
        {customer_id, %{orders: length(records), total: total}}
      end)

    socket
    |> assign(:customers, customers)
    |> assign(:customer_stats, stats)
    |> assign(:page, page)
    |> assign(:page_count, page_count)
  end

  defp stat(stats, id), do: Map.get(stats, id, %{orders: 0, total: Decimal.new(0)})
  defp format_money(amount), do: "৳" <> Decimal.to_string(Decimal.round(amount, 2), :normal)

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
