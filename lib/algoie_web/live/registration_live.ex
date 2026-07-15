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
        {:ok, %{tenant: tenant, user: _user, store: store}} ->
          store_tenant = "tenant_#{tenant.id}"

          case Ash.update(store, %{slug: store_slug},
                 action: :update,
                 actor: :system,
                 tenant: store_tenant
               ) do
            {:ok, updated_store} ->
              case Ash.read_one(StoreRegistry,
                     query: [filter: [store_id: updated_store.id]],
                     authorize?: false
                   ) do
                {:ok, registry} ->
                  registry
                  |> Ecto.Changeset.change(%{slug: store_slug})
                  |> Algoie.Repo.update(prefix: "public")

                _ ->
                  :ok
              end

              {:noreply,
               socket
               |> assign(:step, :success)
               |> assign(:email, email)}

            {:error, _} ->
              {:noreply,
               socket
               |> assign(:step, :success)
               |> assign(:email, email)}
          end

        {:error, changeset} ->
          error_message =
            cond do
              is_struct(changeset) and Map.has_key?(changeset, :errors) and changeset.errors != [] ->
                changeset.errors
                |> Enum.map(fn
                  %{field: field, message: msg} -> "#{field} #{msg}"
                  other -> inspect(other)
                end)
                |> Enum.join(", ")

              is_struct(changeset) and Map.has_key?(changeset, :valid?) and
                  changeset.valid? == false ->
                "Validation failed. Please check your inputs."

              is_binary(changeset) ->
                changeset

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
