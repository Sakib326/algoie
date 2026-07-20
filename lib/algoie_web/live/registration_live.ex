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
     |> assign(:password_strength, nil)
     |> assign(:pending_registration, nil)
     |> assign(:otp_form, to_form(%{"code" => ""}, as: :otp))
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

    socket =
      socket
      |> assign(:password_strength, compute_password_strength(params["password"] || ""))

    if slug == "" do
      {:noreply, assign(socket, slug_available: nil)}
    else
      if String.length(slug) >= 3 do
        if timer = socket.assigns.slug_debounce_timer, do: Process.cancel_timer(timer)

        timer = Process.send_after(self(), {:check_slug, slug}, 400)
        {:noreply, assign(socket, slug_debounce_timer: timer, slug_available: nil)}
      else
        {:noreply, assign(socket, slug_available: false)}
      end
    end
  end

  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> assign(:password_strength, compute_password_strength(params["password"] || ""))}
  end

  def handle_event("register", params, socket) do
    registration_params = Map.get(params, "registration", params)

    with :ok <- validate_required_fields(registration_params),
         :ok <- validate_email_unique(registration_params["email"]),
         :ok <- validate_slug_available(registration_params["store_slug"]),
         :ok <- validate_password_match(registration_params),
         :ok <- validate_password_length(registration_params) do
      email = registration_params["email"]

      case Algoie.Accounts.EmailOtp.issue(email, :platform_registration) do
        {:ok, code} ->
          Algoie.Notifications.verification_code(email, code, :registration)

          {:noreply,
           socket
           |> assign(:step, :otp)
           |> assign(:pending_registration, registration_params)
           |> assign(:otp_form, to_form(%{"code" => ""}, as: :otp))
           |> put_flash(:info, "We sent a 6-digit verification code to #{email}")}

        {:error, :rate_limited} ->
          {:noreply,
           put_flash(socket, :error, "Please wait a minute before requesting another code")}

        {:error, _error} ->
          {:noreply, put_flash(socket, :error, "We could not send the verification code")}
      end
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("verify_registration", %{"otp" => %{"code" => code}}, socket) do
    params = socket.assigns.pending_registration

    case Algoie.Accounts.EmailOtp.verify(
           params["email"],
           :platform_registration,
           "platform",
           code
         ) do
      :ok -> create_store(socket, params)
      {:error, reason} -> {:noreply, put_flash(socket, :error, otp_error(reason))}
    end
  end

  def handle_event("back_to_registration", _params, socket) do
    {:noreply, assign(socket, :step, :form)}
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

    assign(socket, slug_available: available?, slug_debounce_timer: nil)
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

  defp create_store(socket, params) do
    %{
      "business_name" => business_name,
      "store_slug" => store_slug,
      "email" => email,
      "password" => password
    } = params

    case Algoie.Tenants.Provisioner.create_tenant_with_setup(%{
           name: business_name,
           owner_email: email,
           owner_name: business_name,
           owner_password: password
         }) do
      {:ok, %{tenant: tenant, store: store}} ->
        store_tenant = "tenant_#{tenant.id}"

        with {:ok, updated_store} <-
               Ash.update(store, %{slug: store_slug},
                 action: :update,
                 actor: :system,
                 tenant: store_tenant
               ) do
          update_registry_slug(updated_store.id, store_slug)
          Algoie.Notifications.welcome_owner(email, updated_store.name)
        end

        {:noreply, socket |> assign(:step, :success) |> assign(:email, email)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, registration_error(error))}
    end
  end

  defp update_registry_slug(store_id, slug) do
    case Ash.read_one(StoreRegistry, query: [filter: [store_id: store_id]], authorize?: false) do
      {:ok, registry} when not is_nil(registry) ->
        registry
        |> Ecto.Changeset.change(%{slug: slug})
        |> Algoie.Repo.update(prefix: "public")

      _ ->
        :ok
    end
  end

  defp registration_error(error) when is_binary(error), do: error
  defp registration_error(error), do: error |> Ash.Error.to_error_class() |> Exception.message()

  defp otp_error(:expired_code), do: "The verification code expired. Request a new code."
  defp otp_error(:too_many_attempts), do: "Too many incorrect attempts. Request a new code."
  defp otp_error(_), do: "The verification code is incorrect."

  defp validate_slug_available(slug) do
    case Ash.read_one(StoreRegistry, query: [filter: [slug: slug]], authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, _} -> {:error, "This store URL is already taken"}
      _ -> :ok
    end
  end

  defp validate_email_unique(email) do
    alias Algoie.Accounts.User

    case Ash.read_one(User, query: [filter: [email: email]], authorize?: false) do
      {:ok, nil} -> :ok
      {:ok, _} -> {:error, "This email is already registered"}
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

  defp compute_password_strength(password) do
    cond do
      password == "" ->
        nil

      String.length(password) < 6 ->
        1

      true ->
        score = 1
        score = if String.length(password) >= 8, do: score + 1, else: score
        score = if Regex.match?(~r/[A-Z]/, password), do: score + 1, else: score
        score = if Regex.match?(~r/[0-9]/, password), do: score + 1, else: score
        score = if Regex.match?(~r/[^A-Za-z0-9]/, password), do: score + 1, else: score
        min(score, 4)
    end
  end
end
