defmodule AlgoieWeb.SalesReportExportController do
  use AlgoieWeb, :controller

  alias Algoie.Repo
  alias Algoie.Reports.{SimplePDF, SimpleXLSX}

  def export(conn, %{"format" => format} = params) when format in ["pdf", "xlsx"] do
    with {:ok, context} <- authorized_context(conn),
         {:ok, orders} <- load_orders(context, params) do
      filename = "sales-report-#{Date.utc_today()}.#{format}"

      case format do
        "xlsx" -> send_xlsx(conn, orders, context.store_name, filename)
        "pdf" -> send_pdf(conn, orders, context.store_name, filename)
      end
    else
      {:error, :unauthenticated} ->
        conn |> put_flash(:error, "Sign in to export reports.") |> redirect(to: "/sign-in")

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> text("You do not have access to this store report.")

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> text("The sales report could not be exported.")
    end
  end

  def export(conn, _params),
    do: conn |> put_status(:not_found) |> text("Unsupported export format")

  defp authorized_context(conn) do
    user = conn.assigns[:current_user]
    store = conn.assigns[:store]
    tenant = get_session(conn, "store_tenant")

    cond do
      is_nil(user) ->
        {:error, :unauthenticated}

      is_nil(store) or is_nil(tenant) ->
        {:error, :forbidden}

      true ->
        case Algoie.Accounts.UserContext.find_store_access(user.id, store.id) do
          {:ok, access} ->
            if access.tenant == tenant and "reports.view" in access.permissions do
              {:ok, %{tenant: tenant, store_id: to_string(store.id), store_name: store.name}}
            else
              {:error, :forbidden}
            end

          _ ->
            {:error, :forbidden}
        end
    end
  end

  defp load_orders(context, params) do
    cutoff = cutoff(params["period"])
    status = normalize_status(params["status"])
    search = "%#{escape_like(String.trim(params["q"] || ""))}%"

    Repo.query(
      """
      SELECT order_number, inserted_at, customer_name, customer_email, status,
             payment_status, subtotal_amount, discount_amount, shipping_amount, total_amount
      FROM \"#{context.tenant}\".orders
      WHERE store_id::text = $1
        AND ($2::timestamptz IS NULL OR inserted_at >= $2)
        AND ($3::text IS NULL OR status = $3)
        AND ($4 = '%%' OR order_number ILIKE $4 ESCAPE '\\' OR customer_name ILIKE $4 ESCAPE '\\' OR coalesce(customer_email, '') ILIKE $4 ESCAPE '\\')
      ORDER BY inserted_at DESC
      """,
      [context.store_id, cutoff, status, search]
    )
    |> case do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &order_map/1)}
      error -> error
    end
  end

  defp order_map([
         number,
         date,
         name,
         email,
         status,
         payment,
         subtotal,
         discount,
         shipping,
         total
       ]) do
    %{
      number: number,
      date: date,
      customer: name,
      email: email,
      status: status,
      payment: payment,
      subtotal: subtotal,
      discount: discount,
      shipping: shipping,
      total: total
    }
  end

  defp send_xlsx(conn, orders, store_name, filename) do
    binary = SimpleXLSX.render(store_name, orders)

    send_download(conn, {:binary, binary},
      filename: filename,
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
  end

  defp send_pdf(conn, orders, store_name, filename) do
    binary = SimplePDF.render_sales(store_name, orders)
    send_download(conn, {:binary, binary}, filename: filename, content_type: "application/pdf")
  end

  defp cutoff(period) when period in ["7", "30", "90", "365"],
    do: DateTime.add(DateTime.utc_now(), -String.to_integer(period), :day)

  defp cutoff(_), do: nil

  defp normalize_status(status)
       when status in ~w(pending pre_order confirmed fulfilled cancelled), do: status

  defp normalize_status(_), do: nil

  defp escape_like(value),
    do:
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
end
