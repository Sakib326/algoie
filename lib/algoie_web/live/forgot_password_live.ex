defmodule AlgoieWeb.ForgotPasswordLive do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Accounts.{EmailOtp, User}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset password")
     |> assign(:step, :request)
     |> assign(:email, nil)
     |> assign(:form, to_form(%{"email" => ""}, as: :reset))}
  end

  @impl true
  def handle_event("request_code", %{"reset" => %{"email" => email}}, socket) do
    email = email |> String.trim() |> String.downcase()

    delivery_result =
      case find_user(email) do
        %User{} ->
          case EmailOtp.issue(email, :platform_password_reset) do
            {:ok, code} -> Algoie.Notifications.verification_code(email, code, :password_reset)
            _ -> :ok
          end

        nil ->
          :ok
      end

    case delivery_result do
      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The email service is unavailable. Check its configuration and try again."
         )}

      _result ->
        {:noreply,
         socket
         |> assign(:step, :verify)
         |> assign(:email, email)
         |> assign(
           :form,
           to_form(
             %{"code" => "", "password" => "", "password_confirmation" => ""},
             as: :reset
           )
         )
         |> put_flash(:info, "If that account exists, a verification code has been sent.")}
    end
  end

  def handle_event("reset_password", %{"reset" => params}, socket) do
    with :ok <- validate_passwords(params),
         :ok <-
           EmailOtp.verify(
             socket.assigns.email,
             :platform_password_reset,
             "platform",
             params["code"]
           ),
         %User{} = user <- find_user(socket.assigns.email),
         {:ok, _user} <-
           Ash.update(user, %{password: params["password"]},
             action: :reset_password,
             actor: :system
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Password updated. You can now sign in.")
       |> push_navigate(to: ~p"/sign-in")}
    else
      nil -> {:noreply, put_flash(socket, :error, "The verification code is invalid")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  defp find_user(email) do
    User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one!(authorize?: false)
  end

  defp validate_passwords(params) do
    cond do
      String.length(params["password"] || "") < 8 -> {:error, :short_password}
      params["password"] != params["password_confirmation"] -> {:error, :password_mismatch}
      true -> :ok
    end
  end

  defp error_text(:expired_code), do: "The code expired. Request a new one."
  defp error_text(:too_many_attempts), do: "Too many attempts. Request a new code."
  defp error_text(:short_password), do: "Password must be at least 8 characters."
  defp error_text(:password_mismatch), do: "Passwords do not match."
  defp error_text(_), do: "The verification code is invalid."
end
