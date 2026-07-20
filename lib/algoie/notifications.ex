defmodule Algoie.Notifications do
  @moduledoc "Transactional email notifications for account and commerce events."

  import Swoosh.Email

  require Logger

  alias Algoie.Mailer

  def verification_code(email, code, purpose) do
    title = if purpose == :registration, do: "Verify your email", else: "Reset your password"

    deliver_async(purpose, email, fn ->
      base_email(email, "#{code} is your Algoie verification code")
      |> bodies(
        title,
        "Your verification code is #{code}. It expires in 10 minutes and can only be used once.",
        nil,
        nil
      )
    end)
  end

  def welcome_owner(email, store_name) do
    deliver_async(:welcome_owner, email, fn ->
      base_email(email, "Welcome to Algoie")
      |> bodies(
        "Your store is ready",
        "#{store_name} has been created. You can now add products, configure delivery, and invite your team.",
        "Open dashboard",
        dashboard_url()
      )
    end)
  end

  def staff_access(email, store_name, temporary_password \\ nil) do
    deliver_async(:staff_access, email, fn ->
      password_note =
        if temporary_password,
          do: "\n\nTemporary password: #{temporary_password}\nPlease change it after signing in.",
          else: ""

      base_email(email, "You now have access to #{store_name}")
      |> bodies(
        "Store access granted",
        "You have been added to #{store_name} as a staff member.#{password_note}",
        "Open dashboard",
        dashboard_url()
      )
    end)
  end

  def order_confirmation(%{customer_email: email} = order, store_name)
      when is_binary(email) and email != "" do
    deliver_async(:order_confirmation, email, fn ->
      base_email(email, "Order #{order.order_number} confirmed")
      |> bodies(
        "Thanks for your order",
        "#{store_name} received order #{order.order_number}. Total: #{money(order.total_amount)}. We will contact you when its status changes.",
        nil,
        nil
      )
    end)
  end

  def order_confirmation(_order, _store_name), do: :skipped

  def order_status_changed(%{customer_email: email} = order, store_name)
      when is_binary(email) and email != "" do
    status = order.status |> to_string() |> String.replace("_", " ") |> String.capitalize()

    deliver_async(:order_status_changed, email, fn ->
      base_email(email, "Order #{order.order_number}: #{status}")
      |> bodies(
        "Your order status changed",
        "#{store_name} updated order #{order.order_number} to #{status}.",
        nil,
        nil
      )
    end)
  end

  def order_status_changed(_order, _store_name), do: :skipped

  defp deliver_async(event, recipient, email_builder) do
    task = fn ->
      case email_builder.() |> Mailer.deliver() do
        {:ok, metadata} ->
          Logger.info("Email delivered", email_event: event, email_recipient: recipient)
          metadata

        {:error, reason} ->
          Logger.error("Email delivery failed: #{inspect(reason)}",
            email_event: event,
            email_recipient: recipient
          )
      end
    end

    case Process.whereis(Algoie.EmailTaskSupervisor) do
      nil -> Task.start(task)
      _pid -> Task.Supervisor.start_child(Algoie.EmailTaskSupervisor, task)
    end

    :ok
  end

  defp base_email(recipient, subject_line) do
    config = Application.get_env(:algoie, :email, [])

    new()
    |> from({config[:from_name] || "Algoie", config[:from_address] || "noreply@localhost"})
    |> to(recipient)
    |> subject(subject_line)
    |> maybe_reply_to(config[:reply_to])
  end

  defp maybe_reply_to(email, value) when value in [nil, ""], do: email
  defp maybe_reply_to(email, value), do: reply_to(email, value)

  defp bodies(email, heading, message, button_label, button_url) do
    escaped_heading = escape(heading)
    escaped_message = escape(message)

    action =
      if button_label && button_url do
        ~s(<p style="margin:28px 0"><a href="#{escape(button_url)}" style="display:inline-block;background:#4f46e5;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:600">#{escape(button_label)}</a></p>)
      else
        ""
      end

    html = """
    <!doctype html><html><body style="margin:0;background:#f5f5f4;font-family:Inter,Arial,sans-serif;color:#1c1917">
      <div style="max-width:600px;margin:0 auto;padding:40px 20px">
        <div style="background:#fff;border:1px solid #e7e5e4;border-radius:16px;padding:36px">
          <p style="margin:0 0 24px;color:#4f46e5;font-size:20px;font-weight:800">Algoie</p>
          <h1 style="margin:0 0 16px;font-size:26px">#{escaped_heading}</h1>
          <p style="margin:0;color:#57534e;font-size:16px;line-height:1.65">#{escaped_message}</p>
          #{action}
        </div>
        <p style="color:#a8a29e;font-size:12px;text-align:center">This is an automated transactional email.</p>
      </div>
    </body></html>
    """

    email
    |> text_body(text_body(heading, message, button_label, button_url))
    |> html_body(html)
  end

  defp text_body(heading, message, nil, _url), do: "#{heading}\n\n#{message}"

  defp text_body(heading, message, label, url),
    do: "#{heading}\n\n#{message}\n\n#{label}: #{url}"

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp dashboard_url do
    Application.get_env(:algoie, :email, [])[:app_url]
    |> to_string()
    |> String.trim_trailing("/")
    |> Kernel.<>("/dashboard")
  end

  defp money(nil), do: "—"
  defp money(value), do: "BDT " <> Decimal.to_string(Decimal.round(value, 2), :normal)
end
