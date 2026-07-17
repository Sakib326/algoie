defmodule Algoie.Media.Changes.RejectBlankValues do
  @moduledoc """
  Reusable Ash change that strips `nil`/empty-string entries from a list
  attribute.

  Needed because `AlgoieWeb.Components.MediaManagerComponent` submits array
  fields (e.g. `images`) as native HTML `name="field[]"` hidden inputs, which
  requires a leading empty sentinel input so the list can be cleared to `[]`
  when nothing is selected. That sentinel shows up as a blank string in the
  submitted params and must be filtered out before it reaches storage.

  ## Usage

      update :update do
        accept([:images])
        change({Algoie.Media.Changes.RejectBlankValues, attribute: :images})
      end
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    attribute = Keyword.fetch!(opts, :attribute)

    case Ash.Changeset.get_attribute(changeset, attribute) do
      values when is_list(values) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          attribute,
          Enum.reject(values, &(&1 in [nil, ""]))
        )

      _ ->
        changeset
    end
  end
end
