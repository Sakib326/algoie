defmodule AlgoieWeb.OrderLive.Show do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.Order
  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, load_order(socket, id)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Order Details")}
  end

  @impl true
  def handle_event("update_status", %{"status" => new_status}, socket) do
    case parse_status(new_status) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid status")}

      status_atom ->
        case Ash.update(socket.assigns.order, :update_status, %{status: status_atom}) do
          {:ok, order} ->
            {:noreply,
             socket
             |> assign(:order, order)
             |> put_flash(:info, "Order status updated to #{status_atom}")}

          {:error, changeset} ->
            error_msg =
              changeset.errors
              |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
              |> Enum.join(", ")

            {:noreply, put_flash(socket, :error, "Failed to update status: #{error_msg}")}
        end
    end
  end

  defp parse_status("pending"), do: :pending
  defp parse_status("pre_order"), do: :pre_order
  defp parse_status("confirmed"), do: :confirmed
  defp parse_status("fulfilled"), do: :fulfilled
  defp parse_status("cancelled"), do: :cancelled
  defp parse_status(_), do: nil

  defp load_order(socket, id) do
    case Ash.get(Order, id, tenant: socket.assigns.tenant, authorize?: false) do
      {:ok, order} ->
        line_items =
          case Algoie.Orders.OrderLineItem
               |> Ash.Query.filter(order_id == ^order.id)
               |> Ash.Query.for_read(:read)
               |> Ash.read(tenant: socket.assigns.tenant, authorize?: false) do
            {:ok, items} -> items
            _ -> []
          end

        socket
        |> assign(:order, order)
        |> assign(:line_items, line_items)

      _ ->
        socket
        |> assign(:order, nil)
        |> assign(:line_items, [])
    end
  end

  defp allowed_next_statuses(:pending), do: [:pre_order, :confirmed, :cancelled]
  defp allowed_next_statuses(:pre_order), do: [:confirmed, :cancelled]
  defp allowed_next_statuses(:confirmed), do: [:fulfilled, :cancelled]
  defp allowed_next_statuses(_), do: []
end
