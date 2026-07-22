defmodule AlgoieWeb.PlatformAdminLive do
  use AlgoieWeb, :live_view

  alias Algoie.{
    PlatformAISettings,
    PlatformEmailSettings,
    PlatformStorageSettings,
    SocialPublishingSetting
  }

  alias Algoie.Repo

  @tenant_statuses ~w(trial active suspended)
  @store_statuses ~w(active inactive)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "SaaS administration")
     |> assign(:search, "")
     |> assign(:status, "all")
     |> assign(:selected, nil)
     |> assign(:tenant_statuses, @tenant_statuses)
     |> assign(:store_statuses, @store_statuses)
     |> refresh_data()
     |> load_email_form()
     |> load_ai_form()
     |> load_storage_form()
     |> load_social_publishing_form()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = section_for(socket.assigns.live_action)
    section_changed? = socket.assigns[:section] not in [nil, section]

    socket =
      if section_changed? do
        socket
        |> assign(:search, "")
        |> assign(:status, "all")
        |> assign(:filter_form, to_form(%{"status" => "all"}, as: :filter))
      else
        socket
      end

    selected = selected_record(section, params["id"], socket.assigns)

    {:noreply,
     socket
     |> assign(:section, section)
     |> assign(:selected, selected)
     |> assign(:page_title, page_title(section))}
  end

  @impl true
  def handle_event("search", %{"value" => value}, socket) do
    {:noreply, assign(socket, :search, String.trim(value))}
  end

  def handle_event("filter", %{"filter" => %{"status" => status}}, socket) do
    {:noreply, assign(socket, :status, status)}
  end

  def handle_event("tenant-status", %{"id" => id, "status" => status}, socket)
      when status in @tenant_statuses do
    case Repo.query(
           "UPDATE public.tenants SET billing_status = $1, updated_at = now() WHERE id::text = $2",
           [status, id]
         ) do
      {:ok, %{num_rows: 1}} ->
        {:noreply,
         socket |> refresh_data() |> put_flash(:info, "Tenant status updated to #{status}.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Tenant status could not be updated.")}
    end
  end

  def handle_event("tenant-status", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Invalid tenant status.")}

  def handle_event(
        "store-status",
        %{"id" => id, "tenant-id" => tenant_id, "status" => status},
        socket
      )
      when status in @store_statuses do
    with {:ok, tenant_uuid} <- Ecto.UUID.cast(tenant_id),
         {:ok, store_uuid} <- Ecto.UUID.cast(id),
         schema = "tenant_#{tenant_uuid}",
         {:ok, %{num_rows: 1}} <-
           Repo.query(
             "UPDATE \"#{schema}\".stores SET status = $1, updated_at = now() WHERE id::text = $2",
             [status, store_uuid]
           ) do
      {:noreply,
       socket |> refresh_data() |> put_flash(:info, "Store status updated to #{status}.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Store status could not be updated.")}
    end
  end

  def handle_event("store-status", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Invalid store status.")}

  def handle_event("save-email", %{"email" => attrs}, socket) do
    case PlatformEmailSettings.save(attrs) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> load_email_form()
         |> put_flash(:info, "Email configuration saved. New messages use it immediately.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:email_form, to_form(changeset, as: :email))
         |> put_flash(:error, "Email configuration was not saved. Check the highlighted fields.")}
    end
  end

  def handle_event("reset-email-credentials", _params, socket) do
    case PlatformEmailSettings.reset_credentials() do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> load_email_form()
         |> put_flash(:info, "Stored email credentials were removed.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Email credentials could not be reset.")}
    end
  end

  def handle_event("save-ai", %{"ai" => attrs}, socket) do
    case PlatformAISettings.save(attrs) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> load_ai_form()
         |> put_flash(:info, "AI gateway configuration saved.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:ai_form, to_form(changeset, as: :ai))
         |> put_flash(:error, "AI configuration was not saved. Check the highlighted fields.")}
    end
  end

  def handle_event("save-storage", %{"storage" => attrs}, socket) do
    case PlatformStorageSettings.save(attrs) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> load_storage_form()
         |> put_flash(:info, "Media storage configuration saved. New uploads use it immediately.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:storage_form, to_form(changeset, as: :storage))
         |> put_flash(
           :error,
           "Storage configuration was not saved. Check the highlighted fields."
         )}
    end
  end

  def handle_event("save-social-publishing", %{"social_publishing" => attrs}, socket) do
    case SocialPublishingSetting.save(attrs) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> load_social_publishing_form()
         |> put_flash(
           :info,
           "Social publishing configuration saved. New requests use it immediately."
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:social_publishing_form, to_form(changeset, as: :social_publishing))
         |> put_flash(:error, "Social publishing configuration was not saved.")}
    end
  end

  defp refresh_data(socket) do
    tenants = load_tenants()
    stores = load_stores(tenants)

    socket =
      assign(socket,
        tenants: tenants,
        stores: stores,
        stats: stats(tenants, stores),
        filter_form: to_form(%{"status" => socket.assigns[:status] || "all"}, as: :filter)
      )

    refresh_selected(socket)
  end

  defp refresh_selected(%{assigns: %{selected: %{id: id}, section: section}} = socket) do
    assign(socket, :selected, selected_record(section, id, socket.assigns))
  end

  defp refresh_selected(socket), do: socket

  defp load_tenants do
    %{rows: rows} =
      Repo.query!("""
      SELECT id::text, name, owner_email::text, billing_status, inserted_at, updated_at
      FROM public.tenants ORDER BY inserted_at DESC
      """)

    Enum.map(rows, fn [id, name, owner_email, billing_status, inserted_at, updated_at] ->
      %{
        id: id,
        name: name,
        owner_email: owner_email,
        status: billing_status,
        inserted_at: inserted_at,
        updated_at: updated_at
      }
    end)
  end

  defp load_stores(tenants) do
    tenant_names = Map.new(tenants, &{&1.id, &1.name})

    %{rows: registry_rows} =
      Repo.query!(
        "SELECT store_id::text, tenant_id, slug FROM public.store_registry ORDER BY inserted_at DESC"
      )

    Enum.flat_map(registry_rows, fn [store_id, tenant_id, registry_slug] ->
      with {:ok, tenant_uuid} <- Ecto.UUID.cast(tenant_id),
           schema = "tenant_#{tenant_uuid}",
           {:ok, %{rows: [[name, slug, status, email, currency, inserted_at]]}} <-
             Repo.query(
               ~s(SELECT name, slug, status, email, currency, inserted_at FROM "#{schema}".stores WHERE id::text = $1 LIMIT 1),
               [store_id]
             ) do
        [
          %{
            id: store_id,
            tenant_id: tenant_id,
            tenant_name: tenant_names[tenant_id] || "Unknown tenant",
            name: name,
            slug: slug || registry_slug,
            status: status,
            email: email,
            currency: currency,
            inserted_at: inserted_at
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp stats(tenants, stores) do
    %{
      tenants: length(tenants),
      active_tenants: Enum.count(tenants, &(&1.status == "active")),
      trial_tenants: Enum.count(tenants, &(&1.status == "trial")),
      stores: length(stores),
      active_stores: Enum.count(stores, &(&1.status == "active"))
    }
  end

  defp load_email_form(socket) do
    settings = PlatformEmailSettings.get()

    socket
    |> assign(:email_settings, settings)
    |> assign(:email_form, to_form(PlatformEmailSettings.changeset(settings, %{}), as: :email))
  end

  defp load_ai_form(socket) do
    settings = PlatformAISettings.get()

    form_settings = %{
      settings
      | allowed_models_text: Enum.join(settings.allowed_models || [], "\n")
    }

    socket
    |> assign(:ai_settings, settings)
    |> assign(:ai_form, to_form(PlatformAISettings.changeset(form_settings, %{}), as: :ai))
  end

  defp load_storage_form(socket) do
    settings = PlatformStorageSettings.get()

    socket
    |> assign(:storage_settings, settings)
    |> assign(
      :storage_form,
      to_form(PlatformStorageSettings.changeset(settings, %{}), as: :storage)
    )
  end

  defp load_social_publishing_form(socket) do
    settings = SocialPublishingSetting.get()

    socket
    |> assign(:social_publishing_settings, settings)
    |> assign(
      :social_publishing_form,
      to_form(SocialPublishingSetting.changeset(settings, %{}), as: :social_publishing)
    )
  end

  defp section_for(action) when action in [:tenants, :tenant], do: :tenants
  defp section_for(action) when action in [:stores, :store], do: :stores
  defp section_for(:email), do: :email
  defp section_for(:ai), do: :ai
  defp section_for(:storage), do: :storage
  defp section_for(:social), do: :social
  defp section_for(_), do: :overview

  defp selected_record(:tenants, id, assigns) when is_binary(id),
    do: Enum.find(assigns.tenants, &(&1.id == id))

  defp selected_record(:stores, id, assigns) when is_binary(id),
    do: Enum.find(assigns.stores, &(&1.id == id))

  defp selected_record(_, _, _), do: nil

  defp page_title(:tenants), do: "Tenants · SaaS admin"
  defp page_title(:stores), do: "Stores · SaaS admin"
  defp page_title(:email), do: "Email settings · SaaS admin"
  defp page_title(:ai), do: "AI gateway · SaaS admin"
  defp page_title(:storage), do: "Media storage · SaaS admin"
  defp page_title(:social), do: "Social publishing · SaaS admin"
  defp page_title(_), do: "Overview · SaaS admin"

  defp filtered(items, search, status) do
    query = String.downcase(search)

    Enum.filter(items, fn item ->
      matches_status = status == "all" or item.status == status

      text =
        [
          item.name,
          Map.get(item, :owner_email),
          Map.get(item, :slug),
          Map.get(item, :tenant_name)
        ]
        |> Enum.join(" ")
        |> String.downcase()

      matches_status and (query == "" or String.contains?(text, query))
    end)
  end

  defp status_tone("active"), do: "success"
  defp status_tone("trial"), do: "warning"
  defp status_tone("suspended"), do: "error"
  defp status_tone("inactive"), do: "neutral"
  defp status_tone(_), do: "neutral"

  defp short_date(%NaiveDateTime{} = date), do: Calendar.strftime(date, "%d %b %Y")
  defp short_date(%DateTime{} = date), do: Calendar.strftime(date, "%d %b %Y")

  defp storefront_url(slug) do
    AlgoieWeb.PublicURL.store(slug)
  end
end
