defmodule Algoie.Accounts.EmailOtp do
  @moduledoc "Issues and verifies short-lived, single-use email verification codes."

  use Ecto.Schema

  import Ecto.Query

  alias Algoie.Repo

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @schema_prefix "public"
  @ttl_seconds 600
  @max_attempts 5

  schema "email_otps" do
    field :email, :string
    field :purpose, :string
    field :context, :string, default: "platform"
    field :code_hash, :binary
    field :expires_at, :utc_datetime_usec
    field :attempts, :integer, default: 0
    field :consumed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def issue(email, purpose, context \\ "platform") do
    email = normalize_email(email)
    purpose = to_string(purpose)
    context = to_string(context)
    now = DateTime.utc_now()

    recent? =
      from(o in __MODULE__,
        where:
          o.email == ^email and o.purpose == ^purpose and o.context == ^context and
            o.inserted_at > ^DateTime.add(now, -60, :second),
        select: count(o.id) > 0
      )
      |> Repo.one()

    if recent? do
      {:error, :rate_limited}
    else
      code = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(1_000_000)
      code = code |> Integer.to_string() |> String.pad_leading(6, "0")

      Repo.update_all(
        from(o in __MODULE__,
          where:
            o.email == ^email and o.purpose == ^purpose and o.context == ^context and
              is_nil(o.consumed_at)
        ),
        set: [consumed_at: now]
      )

      %__MODULE__{
        email: email,
        purpose: purpose,
        context: context,
        code_hash: hash(code),
        expires_at: DateTime.add(now, @ttl_seconds, :second)
      }
      |> Repo.insert()
      |> case do
        {:ok, _otp} -> {:ok, code}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def verify(email, purpose, context, code) do
    email = normalize_email(email)
    purpose = to_string(purpose)
    context = to_string(context)
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      otp =
        from(o in __MODULE__,
          where:
            o.email == ^email and o.purpose == ^purpose and o.context == ^context and
              is_nil(o.consumed_at),
          order_by: [desc: o.inserted_at],
          limit: 1,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      cond do
        is_nil(otp) ->
          Repo.rollback(:invalid_code)

        DateTime.compare(otp.expires_at, now) != :gt ->
          Repo.rollback(:expired_code)

        otp.attempts >= @max_attempts ->
          Repo.rollback(:too_many_attempts)

        !valid_code?(otp.code_hash, code) ->
          Repo.update_all(from(o in __MODULE__, where: o.id == ^otp.id),
            inc: [attempts: 1]
          )

          Repo.rollback(:invalid_code)

        true ->
          Repo.update_all(from(o in __MODULE__, where: o.id == ^otp.id),
            set: [consumed_at: now]
          )

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_code?(stored_hash, code) when is_binary(code) do
    candidate = hash(String.trim(code))

    byte_size(candidate) == byte_size(stored_hash) and
      Plug.Crypto.secure_compare(candidate, stored_hash)
  end

  defp valid_code?(_stored_hash, _code), do: false

  defp hash(code) do
    :crypto.mac(:hmac, :sha256, otp_secret(), code)
  end

  defp otp_secret do
    Application.fetch_env!(:algoie, :token_signing_secret)
  end

  defp normalize_email(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
