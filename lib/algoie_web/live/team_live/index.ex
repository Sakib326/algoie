defmodule AlgoieWeb.TeamLive.Index do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Accounts.{StoreStaff, User}
  alias Algoie.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :team)
     |> assign(:page_title, "Team & roles")
     |> assign(:page, 1)
     |> assign(:staff_form, staff_form())
     |> load_team()}
  end

  @impl true
  def handle_event("generate_password", _params, socket) do
    params = socket.assigns.staff_form.params || %{}
    password = generate_password()

    {:noreply, assign(socket, :staff_form, staff_form(Map.put(params, "password", password)))}
  end

  def handle_event("create_staff", %{"staff" => params}, socket) do
    if socket.assigns.owner? do
      with {:ok, user, account_created?} <- add_or_create_staff(socket, params) do
        message =
          if account_created? do
            "#{user.name || user.email} was created and added as staff"
          else
            "#{user.name || user.email} was added as staff using their existing account"
          end

        {:noreply,
         socket
         |> assign(:staff_form, staff_form())
         |> load_team()
         |> put_flash(:info, message)}
      else
        {:error, error} ->
          {:noreply,
           socket
           |> assign(:staff_form, staff_form(params))
           |> put_flash(:error, error_text(error))}
      end
    else
      {:noreply, put_flash(socket, :error, "Only an owner can create staff accounts")}
    end
  end

  def handle_event("change_role", %{"membership_id" => id, "role" => role}, socket) do
    with true <- socket.assigns.owner?,
         {:ok, membership} <- membership(socket, id),
         false <- membership.user_id == socket.assigns.current_user.id,
         {:ok, role} <- parse_role(role),
         :ok <- allow_role_change?(socket.assigns.all_memberships, membership, role),
         {:ok, _} <- Ash.update(membership, %{role: role}, AlgoieWeb.Scope.opts(socket)) do
      {:noreply, socket |> load_team() |> put_flash(:info, "Role updated")}
    else
      false -> {:noreply, put_flash(socket, :error, "Only an owner can change roles")}
      true -> {:noreply, put_flash(socket, :error, "You cannot change your own owner role")}
      {:error, message} when is_binary(message) -> {:noreply, put_flash(socket, :error, message)}
      _ -> {:noreply, put_flash(socket, :error, "Role could not be updated")}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with true <- socket.assigns.owner?,
         {:ok, membership} <- membership(socket, id),
         false <- membership.user_id == socket.assigns.current_user.id,
         :ok <- allow_removal?(socket.assigns.all_memberships, membership),
         :ok <- Ash.destroy(membership, AlgoieWeb.Scope.opts(socket)) do
      {:noreply, socket |> load_team() |> put_flash(:info, "Team member removed")}
    else
      false -> {:noreply, put_flash(socket, :error, "Only an owner can remove team members")}
      true -> {:noreply, put_flash(socket, :error, "You cannot remove yourself")}
      {:error, message} when is_binary(message) -> {:noreply, put_flash(socket, :error, message)}
      _ -> {:noreply, put_flash(socket, :error, "Team member could not be removed")}
    end
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(:page, parse_page(page)) |> load_team()}
  end

  defp load_team(socket) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    memberships =
      case StoreStaff
           |> Ash.Query.filter(store_id == ^socket.assigns.store_id)
           |> Ash.Query.sort(inserted_at: :asc)
           |> Ash.read(opts) do
        {:ok, rows} -> rows
        _ -> []
      end

    users = load_users(Enum.map(memberships, & &1.user_id))
    current = Enum.find(memberships, &(&1.user_id == socket.assigns.current_user.id))
    page_size = 10
    page_count = max(ceil(length(memberships) / page_size), 1)
    page = min(socket.assigns.page, page_count)

    socket
    |> assign(:all_memberships, memberships)
    |> assign(:memberships, Enum.slice(memberships, (page - 1) * page_size, page_size))
    |> assign(:users_by_id, users)
    |> assign(:current_role, current && current.role)
    |> assign(:owner?, current && current.role == :owner)
    |> assign(:page, page)
    |> assign(:page_count, page_count)
  end

  defp load_users([]), do: %{}

  defp load_users(ids) do
    dumped_ids = Enum.map(ids, &Ecto.UUID.dump!(to_string(&1)))

    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT id::text, name, email::text FROM public.users WHERE id = ANY($1::uuid[])",
           [dumped_ids]
         ) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [id, name, email] -> {id, %{id: id, name: name, email: email}} end)

      _ ->
        %{}
    end
  end

  defp find_user_by_email(email) do
    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT id::text, name, email::text FROM public.users WHERE lower(email::text) = lower($1) LIMIT 1",
           [String.trim(email)]
         ) do
      {:ok, %{rows: [[id, name, user_email]]}} -> {:ok, %{id: id, name: name, email: user_email}}
      _ -> {:error, :user_not_found}
    end
  end

  defp create_staff_account(socket, params) do
    Repo.transaction(fn ->
      with {:ok, user} <-
             Ash.create(
               User,
               %{
                 name: String.trim(params["name"]),
                 email: String.trim(params["email"]),
                 password: params["password"]
               },
               action: :register_with_password,
               actor: :system
             ),
           {:ok, _membership} <-
             Ash.create(
               StoreStaff,
               %{user_id: user.id, store_id: socket.assigns.store_id, role: :staff},
               AlgoieWeb.Scope.opts(socket)
             ) do
        user
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  defp add_or_create_staff(socket, params) do
    email = String.trim(params["email"] || "")

    if email == "" do
      {:error, "Staff email is required"}
    else
      case find_user_by_email(email) do
        {:ok, user} ->
          case Ash.create(
                 StoreStaff,
                 %{user_id: user.id, store_id: socket.assigns.store_id, role: :staff},
                 AlgoieWeb.Scope.opts(socket)
               ) do
            {:ok, _membership} -> {:ok, user, false}
            {:error, error} -> {:error, error}
          end

        {:error, :user_not_found} ->
          with :ok <- validate_staff_params(params),
               {:ok, user} <- create_staff_account(socket, params) do
            {:ok, user, true}
          end
      end
    end
  end

  defp validate_staff_params(params) do
    cond do
      String.trim(params["name"] || "") == "" ->
        {:error, "Staff name is required"}

      String.trim(params["email"] || "") == "" ->
        {:error, "Staff email is required"}

      String.length(params["password"] || "") < 8 ->
        {:error, "Password must be at least 8 characters"}

      true ->
        :ok
    end
  end

  defp staff_form(params \\ %{}) do
    defaults = %{"name" => "", "email" => "", "password" => generate_password()}
    to_form(Map.merge(defaults, params), as: :staff)
  end

  defp generate_password do
    :crypto.strong_rand_bytes(12)
    |> Base.url_encode64(padding: false)
  end

  defp membership(socket, id) do
    case Enum.find(socket.assigns.all_memberships, &(to_string(&1.id) == id)) do
      nil -> {:error, "Membership not found"}
      row -> {:ok, row}
    end
  end

  defp parse_role("owner"), do: {:ok, :owner}
  defp parse_role("staff"), do: {:ok, :staff}
  defp parse_role(_), do: {:error, "Invalid role"}
  defp owner_count(rows), do: Enum.count(rows, &(&1.role == :owner))

  defp allow_role_change?(rows, %{role: :owner}, :staff) when length(rows) > 0,
    do:
      if(owner_count(rows) > 1, do: :ok, else: {:error, "A store must retain at least one owner"})

  defp allow_role_change?(_, _, _), do: :ok

  defp allow_removal?(rows, %{role: :owner}),
    do: if(owner_count(rows) > 1, do: :ok, else: {:error, "The last owner cannot be removed"})

  defp allow_removal?(_, _), do: :ok

  defp user(users, membership),
    do: Map.get(users, to_string(membership.user_id), %{name: nil, email: "Unknown user"})

  defp error_text(error) when is_binary(error), do: error
  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
