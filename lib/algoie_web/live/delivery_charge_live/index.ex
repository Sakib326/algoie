defmodule AlgoieWeb.DeliveryChargeLive.Index do
  use AlgoieWeb, :live_view

  require Ash.Query
  alias Algoie.Stores.DeliveryCharge

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :delivery_charges)
     |> assign(:page_title, "Delivery charges")
     |> assign(:editing, nil)
     |> assign(:page, 1)
     |> assign_form(%{})
     |> load_rates()}
  end

  @impl true
  def handle_event("validate", %{"rate" => params}, socket),
    do: {:noreply, assign_form(socket, params)}

  def handle_event("save", %{"rate" => params}, socket) do
    attrs = rate_attrs(params, socket.assigns.store_id)

    result =
      case socket.assigns.editing do
        nil -> Ash.create(DeliveryCharge, attrs, AlgoieWeb.Scope.opts(socket))
        rate -> Ash.update(rate, Map.delete(attrs, :store_id), AlgoieWeb.Scope.opts(socket))
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign_form(%{})
         |> load_rates()
         |> put_flash(:info, "Delivery rate saved")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_form(params, AlgoieWeb.FormErrors.to_keyword(error))
         |> put_flash(:error, error_text(error))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Ash.get(DeliveryCharge, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, rate} ->
        {:noreply,
         socket
         |> assign(:editing, rate)
         |> assign_form(
           Map.new(
             [
               name: rate.name,
               city: rate.city,
               area: rate.area,
               charge: rate.charge,
               free_delivery_threshold: rate.free_delivery_threshold,
               estimated_days_min: rate.estimated_days_min,
               estimated_days_max: rate.estimated_days_max,
               priority: rate.priority
             ],
             fn {key, value} -> {to_string(key), value && to_string(value)} end
           )
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _, socket),
    do: {:noreply, socket |> assign(:editing, nil) |> assign_form(%{})}

  def handle_event("toggle", %{"id" => id}, socket) do
    with {:ok, rate} <- Ash.get(DeliveryCharge, id, AlgoieWeb.Scope.opts(socket)),
         {:ok, _} <- Ash.update(rate, %{active?: !rate.active?}, AlgoieWeb.Scope.opts(socket)) do
      {:noreply, load_rates(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update the delivery rate")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, rate} <- Ash.get(DeliveryCharge, id, AlgoieWeb.Scope.opts(socket)),
         :ok <- Ash.destroy(rate, AlgoieWeb.Scope.opts(socket)) do
      {:noreply, load_rates(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "This rate is in use and cannot be deleted")}
    end
  end

  def handle_event("page", %{"page" => page}, socket),
    do: {:noreply, socket |> assign(:page, parse_page(page)) |> load_rates()}

  defp load_rates(socket) do
    rates =
      case Ash.read(
             DeliveryCharge
             |> Ash.Query.filter(store_id == ^socket.assigns.store_id)
             |> Ash.Query.sort(priority: :desc, name: :asc),
             AlgoieWeb.Scope.opts(socket, page: false)
           ) do
        {:ok, rows} -> rows
        _ -> []
      end

    page_size = 10
    page_count = max(ceil(length(rates) / page_size), 1)
    page = min(socket.assigns.page, page_count)

    socket
    |> assign(:rates, Enum.slice(rates, (page - 1) * page_size, page_size))
    |> assign(:page, page)
    |> assign(:page_count, page_count)
  end

  defp assign_form(socket, params, errors \\ []) do
    defaults = %{
      "charge" => "0",
      "estimated_days_min" => "1",
      "estimated_days_max" => "3",
      "priority" => "0"
    }

    assign(
      socket,
      :form,
      to_form(Map.merge(defaults, params), as: :rate, errors: errors, action: :validate)
    )
  end

  defp rate_attrs(params, store_id),
    do: %{
      store_id: store_id,
      name: params["name"],
      city: blank(params["city"]),
      area: blank(params["area"]),
      charge: params["charge"],
      free_delivery_threshold: blank(params["free_delivery_threshold"]),
      estimated_days_min: integer(params["estimated_days_min"], 1),
      estimated_days_max: integer(params["estimated_days_max"], 3),
      priority: integer(params["priority"], 0),
      active?: true
    }

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  defp integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()
  defp format_money(nil), do: "—"
  defp format_money(value), do: "৳" <> Decimal.to_string(Decimal.round(value, 2), :normal)

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
