defmodule Algoie.Accounts.Token do
  use Ash.Resource,
    domain: Algoie.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table("tokens")
    repo(Algoie.Repo)
  end
end
