import Ash.Query

user = Algoie.Accounts.User |> Ash.read!(authorize?: false) |> hd()

store_staff =
  Algoie.Accounts.StoreStaff
  |> Ash.Query.new()
  |> Ash.Query.filter(user_id == ^user.id)
  |> Ash.read!(tenant: "tenant_82c28c95-e068-4d07-ae9d-d74c0d32321d", authorize?: false)
  |> hd()

tenant = "tenant_82c28c95-e068-4d07-ae9d-d74c0d32321d"
store_id = store_staff.store_id

opts = [
  tenant: tenant,
  actor: user,
  context: %{store_id: store_id, tenant: tenant},
  page: false
]

case Ash.read(Algoie.Products.Brand, opts) do
  {:ok, records} ->
    IO.puts(
      "OK! count: #{length(records)}, is_list: #{is_list(records)}, is_struct: #{is_struct(records)}"
    )

  {:error, error} ->
    IO.puts("ERROR: #{inspect(error)}")
end
