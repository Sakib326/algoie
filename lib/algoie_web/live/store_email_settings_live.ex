defmodule AlgoieWeb.StoreEmailSettingsLive do
  use AlgoieWeb, :live_view

  alias Algoie.StoreEmailSettings

  @impl true
  def mount(_params, _session, socket) do
    settings = StoreEmailSettings.get(socket.assigns.tenant, socket.assigns.store_id)

    settings =
      if settings.id do
        settings
      else
        %{
          settings
          | from_name: socket.assigns.store_name,
            from_address: to_string(socket.assigns.current_user.email)
        }
      end

    {:ok,
     socket
     |> assign(:active, :email_settings)
     |> assign(:page_title, "Email settings")
     |> assign(:owner?, socket.assigns.store_role == "owner")
     |> assign(:settings, settings)
     |> assign_form(StoreEmailSettings.changeset(settings, %{}))}
  end

  @impl true
  def handle_event("validate", %{"email" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> StoreEmailSettings.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"email" => params}, socket) do
    if socket.assigns.owner? do
      case StoreEmailSettings.save(socket.assigns.tenant, socket.assigns.store_id, params) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(:settings, settings)
           |> assign_form(StoreEmailSettings.changeset(settings, %{}))
           |> put_flash(:info, success_message(settings))}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign_form(changeset)
           |> put_flash(:error, "Email settings were not saved. Check the highlighted fields.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the store owner can change email settings.")}
    end
  end

  def handle_event("reset", _params, socket) do
    if socket.assigns.owner? do
      case StoreEmailSettings.reset_credentials(socket.assigns.tenant, socket.assigns.store_id) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(:settings, settings)
           |> assign_form(StoreEmailSettings.changeset(settings, %{}))
           |> put_flash(:info, "Custom SMTP credentials removed.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Credentials could not be reset.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the store owner can reset credentials.")}
    end
  end

  def handle_event("test", _params, socket) do
    context = %{tenant: socket.assigns.tenant, store_id: socket.assigns.store_id}

    case Algoie.Notifications.test_email(to_string(socket.assigns.current_user.email), context) do
      {:ok, _metadata} ->
        {:noreply,
         put_flash(socket, :info, "Test email sent to #{socket.assigns.current_user.email}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Test email failed: #{error_text(reason)}")}
    end
  rescue
    error ->
      {:noreply, put_flash(socket, :error, "Test email failed: #{Exception.message(error)}")}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :email))
  defp success_message(%{use_platform: true}), do: "Platform email fallback enabled."
  defp success_message(_settings), do: "Custom store email configuration saved."

  defp error_text({:smtp_runtime_unavailable, _missing}),
    do: "SMTP is not loaded. Restart the application and try again."

  defp error_text({:email_delivery_exception, message}), do: message
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)
end
