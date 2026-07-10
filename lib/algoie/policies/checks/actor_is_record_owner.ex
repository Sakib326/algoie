defmodule Algoie.Policies.Checks.ActorIsRecordOwner do
  @moduledoc """
  Policy check that verifies the actor owns the record being accessed.
  Used for User self-access policies (read/update own profile).
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is the owner of the record"

  @impl true
  def match?(actor, authorizer, _opts) do
    record = authorizer.resource

    case record do
      %{id: id} when not is_nil(actor) ->
        {:ok, actor.id == id}

      _ ->
        {:ok, false}
    end
  end
end
