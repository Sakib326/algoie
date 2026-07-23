defmodule Algoie.Migrations do
  @moduledoc """
  Runs migrations for the public schema and every tenant schema.

  This module lives in the application (rather than only in a Mix task) so the
  same migration workflow is available from an OTP release.
  """

  alias Algoie.Repo

  @public_migrations "priv/repo/migrations"
  @tenant_migrations "priv/repo/tenant_migrations"

  def migrate_all do
    with_repo(fn repo ->
      Ecto.Migrator.run(repo, migrations_path(@public_migrations), :up, all: true)
      migrate_tenants_with_repo(repo)
    end)
  end

  def migrate_tenants do
    with_repo(&migrate_tenants_with_repo/1)
  end

  defp migrate_tenants_with_repo(repo) do
    tenant_schemas(repo)
    |> Enum.map(fn schema ->
      versions =
        Ecto.Migrator.run(repo, migrations_path(@tenant_migrations), :up,
          prefix: schema,
          all: true
        )

      {schema, versions}
    end)
  end

  defp tenant_schemas(repo) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        repo,
        "SELECT id::text FROM public.tenants ORDER BY id",
        []
      )

    Enum.map(rows, fn [tenant_id] -> "tenant_#{tenant_id}" end)
  end

  defp migrations_path(relative_path), do: Application.app_dir(:algoie, relative_path)

  defp with_repo(callback) do
    case Ecto.Migrator.with_repo(Repo, callback) do
      {:ok, result, _apps} -> result
      {:error, reason} -> raise "could not start repository for migrations: #{inspect(reason)}"
    end
  end
end
