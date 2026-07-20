defmodule DebugPolicy do
  use Ash.Policy.SimpleCheck
  def describe(_opts), do: "debug"

  def match?(_actor, authorizer, _opts) do
    IO.inspect(authorizer.context, label: "CONTEXT IN POLICY FOR #{inspect(authorizer.resource)}")
    {:ok, true}
  end
end
