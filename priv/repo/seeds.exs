# Development seed data
# Run with: mix run priv/repo/seeds.exs

alias Algoie.Repo
alias Algoie.Tenants.Provisioner
alias Algoie.Accounts.{User, StoreStaff}
alias Algoie.Stores.Store
alias Algoie.Products.{Product, Variant, Category, Brand, Collection, CollectionProduct}
alias Algoie.Customers.{Customer, Coupon}
alias Algoie.Orders.{Order, OrderLineItem, OrderWorkflow}

import Ecto.Query
require Ash.Query

IO.puts("\n═══ Algoie Development Seed ═══\n")

# ── Clean slate ──────────────────────────────────────────────
IO.puts("Cleaning database...")
Repo.query!("TRUNCATE public.users CASCADE")
Repo.query!("TRUNCATE public.tenants CASCADE")
Repo.query!("TRUNCATE public.store_registry CASCADE")
Repo.query!("TRUNCATE public.tokens CASCADE")

# ── Provision tenant ─────────────────────────────────────────
IO.puts("Provisioning tenant...")

{:ok, _result} =
  Provisioner.create_tenant_with_setup(%{
    name: "Demo Store",
    owner_email: "owner@demo.com",
    owner_name: "Store Owner",
    owner_password: "password123"
  })

# Get tenant ID from public schema
%{id: tenant_id} = Repo.one!(from(t in "tenants", prefix: "public", select: %{id: t.id}))
tenant_id_str = Ecto.UUID.cast!(tenant_id)
schema = "tenant_#{tenant_id_str}"

# Get store and owner using Ash.read
IO.puts("  Schema: #{schema}")
{:ok, [store]} = Ash.read(Store, tenant: schema, authorize?: false)
{:ok, [owner]} = Ash.read(User, tenant: schema, authorize?: false)
IO.puts("  Store: #{store.name} (#{store.slug})")
IO.puts("  Owner: #{owner.email}")

# Create staff user
IO.puts("Creating staff user...")

{:ok, staff} =
  Ash.create(
    User,
    %{email: "staff@demo.com", name: "Store Staff", password: "password123"},
    action: :register_with_password,
    actor: :system,
    tenant: schema
  )

{:ok, _} =
  Ash.create(
    StoreStaff,
    %{user_id: staff.id, store_id: store.id, role: :staff},
    actor: :system,
    tenant: schema
  )

IO.puts("  Staff: #{staff.email}")

# ── Categories ───────────────────────────────────────────────
IO.puts("\nCreating categories...")

categories = [
  {"Electronics", nil},
  {"Smartphones", "Electronics"},
  {"Laptops", "Electronics"},
  {"Audio", "Electronics"},
  {"Clothing", nil},
  {"T-Shirts", "Clothing"},
  {"Jeans", "Clothing"},
  {"Jackets", "Clothing"},
  {"Home & Living", nil},
  {"Furniture", "Home & Living"},
  {"Lighting", "Home & Living"}
]

category_map =
  Enum.reduce(categories, %{}, fn {name, parent_name}, acc ->
    parent_id = if parent_name, do: acc[parent_name]

    {:ok, cat} =
      Ash.create(Category, %{name: name, store_id: store.id, parent_id: parent_id},
        actor: :system,
        tenant: schema
      )

    Map.put(acc, name, cat.id)
  end)

IO.puts("  Created #{map_size(category_map)} categories")

# ── Brands ───────────────────────────────────────────────────
IO.puts("Creating brands...")
brand_names = ["Apex", "Zenith", "Pulse", "Nova", "Vertex", "Echo", "Lume", "Flux"]

brand_map =
  Enum.reduce(brand_names, %{}, fn name, acc ->
    {:ok, brand} =
      Ash.create(Brand, %{name: name, store_id: store.id}, actor: :system, tenant: schema)

    Map.put(acc, name, brand.id)
  end)

IO.puts("  Created #{map_size(brand_map)} brands")

# ── Collections ──────────────────────────────────────────────
IO.puts("Creating collections...")

{:ok, summer} =
  Ash.create(
    Collection,
    %{
      name: "Summer Essentials",
      description: "Must-haves for the summer season",
      store_id: store.id
    },
    actor: :system,
    tenant: schema
  )

{:ok, new_arrivals} =
  Ash.create(
    Collection,
    %{name: "New Arrivals", description: "Fresh from the factory", store_id: store.id},
    actor: :system,
    tenant: schema
  )

{:ok, bestsellers} =
  Ash.create(
    Collection,
    %{name: "Bestsellers", description: "Our most popular products", store_id: store.id},
    actor: :system,
    tenant: schema
  )

IO.puts("  Created 3 collections")

# ── Products ─────────────────────────────────────────────────
IO.puts("Creating products...")

products_data = [
  {"Apex", "Smartphones", "Apex Pro X", "Flagship smartphone with stunning display", :active},
  {"Nova", "Smartphones", "Nova Lite", "Affordable smartphone with great camera", :active},
  {"Pulse", "Smartphones", "Pulse Max", "Performance-focused smartphone", :draft},
  {"Zenith", "Laptops", "Zenith Ultrabook", "Ultra-thin laptop for professionals", :active},
  {"Vertex", "Laptops", "Vertex Gaming", "High-performance gaming laptop", :active},
  {"Apex", "Laptops", "Apex Book", "Everyday laptop for students", :active},
  {"Echo", "Audio", "Echo Buds Pro", "True wireless earbuds with ANC", :active},
  {"Lume", "Audio", "Lume Speaker", "Portable Bluetooth speaker", :active},
  {"Pulse", "Audio", "Pulse Headphones", "Over-ear wireless headphones", :active},
  {"Flux", "T-Shirts", "Classic Tee", "Premium cotton t-shirt", :active},
  {"Nova", "T-Shirts", "Graphic Tee", "Limited edition graphic tee", :active},
  {"Echo", "T-Shirts", "Essential Tee", "Everyday essential t-shirt", :active},
  {"Vertex", "Jeans", "Slim Fit Jeans", "Modern slim fit jeans", :active},
  {"Apex", "Jeans", "Classic Denim", "Classic straight fit jeans", :active},
  {"Zenith", "Jackets", "Bomber Jacket", "Classic bomber jacket", :active},
  {"Lume", "Jackets", "Rain Jacket", "Waterproof rain jacket", :active},
  {"Vertex", "Furniture", "Modern Chair", "Ergonomic modern chair", :active},
  {"Echo", "Furniture", "Coffee Table", "Minimalist coffee table", :active},
  {"Flux", "Furniture", "Standing Desk", "Adjustable standing desk", :active},
  {"Lume", "Lighting", "Desk Lamp", "LED desk lamp with dimmer", :active},
  {"Apex", "Lighting", "Floor Lamp", "Modern floor lamp", :active},
  {"Pulse", "Electronics", "Pulse Tablet", "Coming soon tablet", :draft},
  {"Nova", "Smartphones", "Nova Mini", "Compact smartphone", :draft},
  {"Zenith", "Laptops", "Zenith Pro", "Professional workstation", :archived},
  {"Echo", "Audio", "Echo Classic", "Legacy headphones", :archived},
  {"Flux", "Clothing", "Vintage Tee", "Discontinued vintage tee", :archived}
]

cat_list = Map.values(category_map)

products =
  Enum.map(products_data, fn {brand_name, _cat_name, name, desc, status} ->
    brand_id = brand_map[brand_name]
    cat_id = Enum.at(cat_list, :rand.uniform(length(cat_list)) - 1)

    {:ok, product} =
      Ash.create(
        Product,
        %{
          name: name,
          description: desc,
          store_id: store.id,
          brand_id: brand_id,
          category_id: cat_id,
          status: status
        },
        actor: :system,
        tenant: schema
      )

    product
  end)

IO.puts("  Created #{length(products)} products")

# ── Variants ─────────────────────────────────────────────────
IO.puts("Creating variants...")

variant_count =
  Enum.reduce(products, 0, fn product, acc ->
    variant_count = if product.status == :active, do: Enum.random([2, 3]), else: 1

    Enum.each(1..variant_count, fn i ->
      sku =
        String.replace(String.downcase(product.name), " ", "-") <>
          "-#{String.slice(product.id, 0, 4)}-#{i}"

      price =
        Decimal.new(
          "#{Enum.random([19.99, 29.99, 49.99, 79.99, 99.99, 129.99, 199.99, 299.99, 499.99, 799.99])}"
        )

      stock = if product.status == :active, do: Enum.random([5, 10, 25, 50, 100]), else: 0

      {:ok, _} =
        Ash.create(
          Variant,
          %{
            product_id: product.id,
            store_id: store.id,
            sku: sku,
            price: price,
            stock: stock,
            track_inventory?: true
          },
          actor: :system,
          tenant: schema
        )
    end)

    acc + variant_count
  end)

IO.puts("  Created #{variant_count} variants")

# ── Add products to collections ──────────────────────────────
IO.puts("Adding products to collections...")
active_products = Enum.filter(products, &(&1.status == :active))

Enum.take(active_products, 6)
|> Enum.each(fn p ->
  Ash.create(CollectionProduct, %{collection_id: summer.id, product_id: p.id},
    actor: :system,
    tenant: schema
  )
end)

Enum.take(active_products, -6)
|> Enum.each(fn p ->
  Ash.create(CollectionProduct, %{collection_id: new_arrivals.id, product_id: p.id},
    actor: :system,
    tenant: schema
  )
end)

Enum.slice(active_products, 6, 6)
|> Enum.each(fn p ->
  Ash.create(CollectionProduct, %{collection_id: bestsellers.id, product_id: p.id},
    actor: :system,
    tenant: schema
  )
end)

IO.puts("  Added products to collections")

# ── Customers ────────────────────────────────────────────────
IO.puts("Creating customers...")

customers =
  Enum.reduce(1..5, [], fn i, acc ->
    {:ok, customer} =
      Ash.create(
        Customer,
        %{
          name: "Customer #{i}",
          email: "customer#{i}@example.com",
          phone: "+155500#{String.pad_leading(to_string(i), 4, "0")}",
          store_id: store.id
        },
        actor: :system,
        tenant: schema
      )

    [customer | acc]
  end)

IO.puts("  Created #{length(customers)} customers")

# ── Coupons ──────────────────────────────────────────────────
IO.puts("Creating coupons...")
now = DateTime.utc_now()

{:ok, _} =
  Ash.create(
    Coupon,
    %{
      code: "SUMMER10",
      discount_type: :percent,
      discount_value: Decimal.new("10"),
      store_id: store.id,
      starts_at: DateTime.add(now, -7, :day),
      expires_at: DateTime.add(now, 30, :day)
    },
    actor: :system,
    tenant: schema
  )

{:ok, _} =
  Ash.create(
    Coupon,
    %{
      code: "FLAT20",
      discount_type: :fixed,
      discount_value: Decimal.new("20"),
      store_id: store.id,
      starts_at: DateTime.add(now, -1, :day),
      expires_at: DateTime.add(now, 60, :day),
      min_order_value: Decimal.new("100")
    },
    actor: :system,
    tenant: schema
  )

IO.puts("  Created 2 coupons")

# ── Orders ───────────────────────────────────────────────────
IO.puts("Creating orders...")

active_variants =
  Variant
  |> Ash.Query.filter(store_id == ^store.id)
  |> Ash.Query.for_read(:read)
  |> Ash.read!(tenant: schema, authorize?: false)
  |> Enum.filter(fn v -> v.stock > 0 end)

customer_list = Enum.reverse(customers)
statuses = [:pending, :confirmed, :fulfilled, :cancelled, :pending, :confirmed]

Enum.each(Enum.zip(customer_list, statuses), fn {customer, status} ->
  picked = Enum.take_random(active_variants, Enum.random([1, 2]))

  variant_quantities =
    Enum.map(picked, fn v ->
      qty = min(Enum.random([1, 2]), v.stock)
      %{variant_id: v.id, quantity: qty, store_id: store.id}
    end)

  case OrderWorkflow.create_order(
         schema,
         %{
           store_id: store.id,
           customer_id: customer.id,
           address: %{
             label: "Home",
             recipient_name: customer.name,
             phone: customer.phone,
             address_line1: "#{Enum.random(10..99)} Seed Street",
             city: "Dhaka",
             country: "Bangladesh",
             default?: true
           },
           variant_quantities: variant_quantities
         },
         owner
       ) do
    {:ok, order} ->
      if status != :pending do
        changeset = Ash.Changeset.for_update(order, :update_status, %{status: status})
        Ash.update(changeset, actor: :system)
      end

    {:error, reason} ->
      IO.puts("  Order error: #{inspect(reason)}")
  end
end)

IO.puts("  Created orders in various states")

IO.puts("\n═══ Seed Complete ═══")
IO.puts("\nAccounts:")
IO.puts("  Owner: owner@demo.com / password123")
IO.puts("  Staff: staff@demo.com / password123")
IO.puts("\nStore: #{store.slug}")
IO.puts("  URL: http://#{store.slug}.localhost:4000")
IO.puts("  Dashboard: http://localhost:4000/dashboard")
IO.puts("")
