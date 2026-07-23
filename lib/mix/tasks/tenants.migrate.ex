defmodule Mix.Tasks.Tenants.Migrate do
  use Mix.Task

  @shortdoc "Migrates every existing tenant schema"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    Algoie.Migrations.migrate_tenants()
    |> report()
  end

  defp report(results) do
    Enum.each(results, fn {schema, versions} ->
      Mix.shell().info("#{schema}: #{length(versions)} migration(s) applied")
    end)
  end
end
