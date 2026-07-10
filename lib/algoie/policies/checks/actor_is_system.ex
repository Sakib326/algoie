defmodule Algoie.Policies.Checks.ActorIsSystem do
  @moduledoc """
  Simple check that verifies the actor is the :system actor.
  Used for administrative operations like tenant creation.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is the system"

  @impl true
  def match?(actor, _context, _opts) do
    {:ok, actor == :system}
  end
end
