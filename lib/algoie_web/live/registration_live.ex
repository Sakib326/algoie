defmodule AlgoieWeb.RegistrationLive do
  use AlgoieWeb, :live_view

  alias Algoie.Stores.StoreRegistry

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create Your Store")
     |> assign(:step, :form)
     |> assign(:slug_available, nil)
     |> assign(:slug_debounce_timer, nil)
     |> assign(
       :form,
       to_form(%{
         "business_name" => "",
         "store_name" => "",
         "store_slug" => "",
         "email" => "",
         "password" => "",
         "password_confirmation" => ""
       })
     )}
  end

  @impl true
  def handle_event("validate", %{"store_slug" => slug} = params, socket) do
    slug =
      slug
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9-]/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    socket = assign(socket, :form, to_form(Map.put(params, "store_slug", slug)))

    if String.length(slug) >= 3 do
      if timer = socket.assigns.slug_debounce_timer, do: Process.cancel_timer(timer)

      timer = Process.send_after(self(), {:check_slug, slug}, 400)
      {:noreply, assign(socket, slug_debounce_timer: timer, slug_available: nil)}
    else
      {:noreply, assign(socket, slug_available: false)}
    end
  end

  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_event("check_slug", %{"slug" => slug}, socket) do
    {:noreply, do_slug_check(socket, slug)}
  end

  def handle_event("register", %{"_target" => _} = params, socket) do
    registration_params = Map.get(params, "registration", params)

    with {:ok, _} <- validate_required_fields(registration_params),
         :ok <- validate_slug_available(registration_params["store_slug"]),
         :ok <- validate_password_match(registration_params),
         :ok <- validate_password_length(registration_params) do
      %{
        "business_name" => business_name,
        "store_name" => _store_name,
        "store_slug" => store_slug,
        "email" => email,
        "password" => password
      } = registration_params

      case Algoie.Tenants.Provisioner.create_tenant_with_setup(%{
             name: business_name,
             owner_email: email,
             owner_name: business_name,
             owner_password: password
           }) do
        {:ok, %{tenant: _tenant, user: _user, store: store}} ->
          # Override the auto-generated slug with user's chosen slug
          store_tenant =
            "tenant_#{store.__metadata__.tenant |> String.replace_leading("tenant_", "")}"

          case Ash.update(store, %{slug: store_slug},
                 action: :update,
                 actor: :system,
                 tenant: store_tenant
               ) do
            {:ok, updated_store} ->
              # Update registry entry
              Algoie.Repo.query!(
                "UPDATE public.store_registry SET slug = '#{store_slug}' WHERE store_id = '#{updated_store.id}'"
              )

              {:noreply,
               socket
               |> assign(:step, :success)
               |> assign(:email, email)
               |> assign(:password, password)}

            {:error, _} ->
              # Store was created with auto-slug, that's fine
              {:noreply,
               socket
               |> assign(:step, :success)
               |> assign(:email, email)
               |> assign(:password, password)}
          end

        {:error, changeset} ->
          error_message =
            cond do
              changeset.errors != [] ->
                changeset.errors
                |> Enum.map(fn
                  %{field: field, message: msg} -> "#{field} #{msg}"
                  other -> inspect(other)
                end)
                |> Enum.join(", ")

              changeset.valid? == false ->
                "Validation failed. Please check your inputs."

              true ->
                "Registration failed. Please try again."
            end

          {:noreply, put_flash(socket, :error, error_message)}
      end
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_info({:check_slug, slug}, socket) do
    {:noreply, do_slug_check(socket, slug)}
  end

  defp do_slug_check(socket, slug) do
    available? =
      case Ash.read_one(StoreRegistry, query: [filter: [slug: slug]], authorize?: false) do
        {:ok, nil} -> true
        {:ok, _} -> false
        _ -> true
      end

    {:noreply, assign(socket, slug_available: available?, slug_debounce_timer: nil)}
  end

  defp validate_required_fields(params) do
    required = [
      "business_name",
      "store_name",
      "store_slug",
      "email",
      "password",
      "password_confirmation"
    ]

    missing = Enum.filter(required, &(params[&1] in [nil, ""]))

    if missing == [], do: :ok, else: {:error, "Please fill in all fields"}
  end

  defp validate_slug_available(slug) do
    case Ash.read_one(StoreRegistry, query: [filter: [slug: slug]], authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, _} -> {:error, "This store URL is already taken"}
      _ -> :ok
    end
  end

  defp validate_password_match(params) do
    if params["password"] == params["password_confirmation"],
      do: :ok,
      else: {:error, "Passwords do not match"}
  end

  defp validate_password_length(params) do
    if String.length(params["password"] || "") >= 8,
      do: :ok,
      else: {:error, "Password must be at least 8 characters"}
  end
end
