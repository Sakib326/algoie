defmodule Algoie.Repo do
  use AshPostgres.Repo, otp_app: :algoie

  def installed_extensions do
    ["ash-functions"]
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  @doc """
  Create a new tenant schema.
  """
  def create_tenant_schema(schema_name) do
    query = "CREATE SCHEMA IF NOT EXISTS \"#{schema_name}\""

    case Ecto.Adapters.SQL.query(__MODULE__, query, []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
