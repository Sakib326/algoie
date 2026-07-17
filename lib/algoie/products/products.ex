defmodule Algoie.Products do
  use Ash.Domain

  resources do
    resource(Algoie.Products.Product)
    resource(Algoie.Products.Variant)
    resource(Algoie.Products.Category)
    resource(Algoie.Products.Brand)
    resource(Algoie.Products.Collection)
    resource(Algoie.Products.CollectionProduct)
    resource(Algoie.Products.Tag)
    resource(Algoie.Products.ProductTag)
    resource(Algoie.Products.ProductImage)
    resource(Algoie.Products.ProductCategory)
  end
end
