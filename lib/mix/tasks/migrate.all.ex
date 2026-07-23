defmodule Mix.Tasks.Migrate.All do
  use Mix.Task

  @shortdoc "Migrates the public schema and every existing tenant schema"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    Algoie.Migrations.migrate_all()
    |> Enum.each(fn {schema, versions} ->
      Mix.shell().info("#{schema}: #{length(versions)} tenant migration(s) applied")
    end)
  end
end
