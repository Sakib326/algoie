defmodule Algoie.Orders do
  use Ash.Domain

  resources do
    resource(Algoie.Orders.Order)
    resource(Algoie.Orders.OrderLineItem)
  end
end
