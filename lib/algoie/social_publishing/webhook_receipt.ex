defmodule Algoie.SocialPublishing.WebhookReceipt do
  use Ecto.Schema

  alias Algoie.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "zernio_webhook_receipts" do
    field :event_id, :string
    field :event, :string
    field :provider_account_id, :string
    field :processed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_once(attrs) do
    now = DateTime.utc_now()

    row =
      attrs
      |> Map.take([:event_id, :event, :provider_account_id, :processed_at])
      |> Map.put(:id, Ecto.UUID.generate())
      |> Map.put_new(:processed_at, now)
      |> Map.put(:inserted_at, now)

    case Repo.insert_all(__MODULE__, [row], on_conflict: :nothing, conflict_target: :event_id) do
      {1, _} -> :new
      {0, _} -> :duplicate
    end
  end
end
