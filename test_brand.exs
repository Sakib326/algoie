import Ash.Query

user = Algoie.Accounts.User |> Ash.read!(authorize?: false) |> hd()
store_user = Algoie.Stores.StoreStaff |> Ash.Query.filter(user_id == ^user.id) |> Ash.read!(authorize?: false) |> hd()
tenant = "tenant_#{store_user.store_id}"

opts = [tenant: tenant, actor: user, page: false]

case Ash.read(Algoie.Products.Brand, opts) do
  {:ok, records} -> IO.puts("OK! is_list: #{is_list(records)}, is_struct: #{is_struct(records)}")
  {:error, error} -> IO.puts("ERROR: #{inspect(error)}")
end
