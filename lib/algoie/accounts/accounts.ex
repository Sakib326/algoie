defmodule Algoie.Accounts do
  use Ash.Domain

  resources do
    resource(Algoie.Accounts.Tenant)
    resource(Algoie.Accounts.TenantMembership)
    resource(Algoie.Accounts.User)
    resource(Algoie.Accounts.Token)
    resource(Algoie.Accounts.StoreStaff)
  end
end
