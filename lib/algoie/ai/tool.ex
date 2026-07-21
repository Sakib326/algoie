defmodule Algoie.AI.Tool do
  @moduledoc """
  Behaviour for an AI capability backed by a domain-owned operation.

  A tool receives already validated arguments and an immutable execution context.
  It must delegate to Ash actions; it must not call Repo or issue SQL.
  """

  @type definition :: %{
          required(:id) => String.t(),
          required(:version) => pos_integer(),
          required(:risk) =>
            :read_only | :draft | :write | :external_effect | :destructive_or_financial,
          required(:input_schema) => map(),
          required(:handler) => (map(), map() -> {:ok, map()} | {:error, term()})
        }

  @callback definition() :: definition()
end
