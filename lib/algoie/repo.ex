defmodule Algoie.Repo do
  use Ecto.Repo,
    otp_app: :algoie,
    adapter: Ecto.Adapters.Postgres
end
