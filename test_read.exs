import Ash.Query

user = Algoie.Accounts.User |> Ash.read!(authorize?: false) |> hd()
store_staff = Algoie.Accounts.StoreStaff |> Ash.Query.new() |> Ash.Query.filter(user_id == ^user.id) |> Ash.read!(authorize?: false) |> hd()
tenant = "tenant_#{store_staff.store_id}"

opts = [
  tenant: tenant,
  actor: user,
  context: %{store_id: store_staff.store_id, tenant: tenant},
  page: false
]

case Ash.read(Algoie.Products.Brand, opts) do
  {:ok, records} -> IO.puts("OK! count: #{length(records)}")
  {:error, error} -> IO.puts("ERROR: #{inspect(error)}")
end
