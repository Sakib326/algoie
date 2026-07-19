import Ecto.Query

# let's just inspect the Ash resource
require Ash.Query
IO.inspect(Algoie.Products.Variant |> Ash.Resource.Info.attributes() |> Enum.find(& &1.name == :track_inventory?))
