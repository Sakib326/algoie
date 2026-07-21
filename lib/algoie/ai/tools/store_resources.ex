defmodule Algoie.AI.Tools.StoreResources do
  @moduledoc "Permission-scoped CRUD tools for dashboard commerce resources."

  import Ash.Query

  @areas %{
    "catalog" => %{
      permission: "catalog",
      resources: %{
        "product" =>
          {Algoie.Products.Product,
           [
             :name,
             :slug,
             :description,
             :brand_id,
             :category_id,
             :status,
             :product_type,
             :featured,
             :is_new,
             :attribute_definitions,
             :meta_title,
             :meta_description,
             :tag_ids,
             :tags,
             :category_ids
           ]},
        "variant" =>
          {Algoie.Products.Variant,
           [
             :product_id,
             :sku,
             :price,
             :compare_at_price,
             :cost_price,
             :barcode,
             :stock,
             :reserved_quantity,
             :low_stock_threshold,
             :track_inventory?,
             :option_values,
             :position
           ]},
        "category" =>
          {Algoie.Products.Category,
           [:name, :slug, :description, :image_url, :meta_title, :meta_description, :parent_id]},
        "brand" =>
          {Algoie.Products.Brand,
           [:name, :slug, :description, :image_url, :meta_title, :meta_description]},
        "collection" =>
          {Algoie.Products.Collection, [:name, :slug, :description, :image_url, :active?]},
        "tag" => {Algoie.Products.Tag, [:name, :slug]},
        "media_folder" => {Algoie.Media.MediaFolder, [:name, :parent_id]},
        "media_asset" => {Algoie.Media.MediaAsset, [:alt_text, :folder_id]}
      }
    },
    "customers" => %{
      permission: "customers",
      resources: %{"customer" => {Algoie.Customers.Customer, [:name, :email, :phone]}}
    },
    "discounts" => %{
      permission: "discounts",
      resources: %{
        "coupon" =>
          {Algoie.Customers.Coupon,
           [
             :code,
             :discount_type,
             :discount_value,
             :min_order_value,
             :starts_at,
             :expires_at,
             :usage_limit,
             :active?
           ]},
        "delivery_charge" =>
          {Algoie.Stores.DeliveryCharge,
           [
             :name,
             :city,
             :area,
             :charge,
             :free_delivery_threshold,
             :estimated_days_min,
             :estimated_days_max,
             :priority,
             :active?
           ]}
      }
    }
  }

  def definition do
    Enum.flat_map(@areas, fn {area, config} ->
      resources = Map.keys(config.resources)

      [
        tool(area, "query", resources, :read_only, "#{config.permission}.view", &query/2),
        tool(area, "manage", resources, :write, "#{config.permission}.manage", &manage/2)
      ]
    end) ++
      [
        inventory_management_tool(),
        order_management_tool(),
        order_creation_tool(),
        settings_query_tool(),
        settings_management_tool()
      ]
  end

  defp inventory_management_tool do
    tool = tool("inventory", "manage", ["variant"], :write, "inventory.manage", &manage/2)
    put_in(tool, [:input_schema, "properties", "operation", "enum"], ["update"])
  end

  defp settings_query_tool do
    %{
      id: "query_store_settings",
      version: 1,
      risk: :read_only,
      permissions: ["settings.view"],
      description: "Read the current store's editable settings.",
      input_schema: %{"type" => "object", "properties" => %{}},
      handler: &query_settings/2
    }
  end

  defp settings_management_tool do
    %{
      id: "manage_store_settings",
      version: 1,
      risk: :write,
      permissions: ["settings.manage"],
      description:
        "Update the current store's name, contact, address, branding, domain, invoice, or status settings.",
      input_schema: %{
        "type" => "object",
        "required" => ["attributes"],
        "properties" => %{"attributes" => %{"type" => "object"}}
      },
      handler: &manage_settings/2
    }
  end

  defp tool(area, kind, resources, risk, permission, handler) do
    operation = if kind == "query", do: ["list", "get"], else: ["create", "update", "delete"]

    relationship_help =
      if area == "catalog" and kind == "manage" do
        " Product attributes may include tags as an array of names, tag_ids, or category_ids; these relationships are validated and synchronized."
      else
        ""
      end

    %{
      id: "#{kind}_#{area}",
      version: 1,
      risk: risk,
      permissions: [permission],
      description:
        "#{String.capitalize(kind)} #{Enum.join(resources, ", ")} records in the current store.#{relationship_help}",
      input_schema: %{
        "type" => "object",
        "required" => ["resource", "operation"],
        "properties" => %{
          "resource" => %{"type" => "string", "enum" => resources},
          "operation" => %{"type" => "string", "enum" => operation},
          "id" => %{"type" => "string", "description" => "Required for get, update, and delete"},
          "attributes" => %{"type" => "object", "description" => "Fields to create or update"},
          "search" => %{
            "type" => "string",
            "description" => "Optional name, code, email, SKU, or slug search"
          },
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 50}
        }
      },
      handler: handler
    }
  end

  defp order_management_tool do
    %{
      id: "manage_orders",
      version: 1,
      risk: :write,
      permissions: ["orders.manage"],
      description:
        "Update an order's lifecycle, payment, or fulfillment status in the current store.",
      input_schema: %{
        "type" => "object",
        "required" => ["id", "operation", "attributes"],
        "properties" => %{
          "id" => %{"type" => "string"},
          "operation" => %{
            "type" => "string",
            "enum" => ["update_status", "update_payment", "update_fulfillment"]
          },
          "attributes" => %{"type" => "object"}
        }
      },
      handler: &manage_order/2
    }
  end

  defp order_creation_tool do
    %{
      id: "create_order",
      version: 1,
      risk: :destructive_or_financial,
      permissions: ["orders.manage"],
      description:
        "Create an order for an existing or new customer, validating stock, delivery, and coupons transactionally.",
      input_schema: %{
        "type" => "object",
        "required" => ["address", "items"],
        "properties" => %{
          "customer_id" => %{"type" => "string"},
          "customer" => %{"type" => "object"},
          "address_id" => %{"type" => "string"},
          "address" => %{"type" => "object"},
          "items" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "required" => ["variant_id", "quantity"]
            }
          },
          "coupon_code" => %{"type" => "string"},
          "delivery_charge_id" => %{"type" => "string"},
          "notes" => %{"type" => "string"}
        }
      },
      handler: &create_order/2
    }
  end

  def query(%{"resource" => resource, "operation" => operation} = args, context) do
    with {:ok, {module, _fields}} <- resource_config(resource),
         {:ok, result} <- run_query(module, operation, args, context) do
      {:ok, %{resource: resource, result: result}}
    end
  end

  def manage(%{"resource" => resource, "operation" => operation} = args, context) do
    with {:ok, {module, fields}} <- resource_config(resource),
         {:ok, result} <- run_manage(module, fields, operation, args, context) do
      {:ok, %{resource: resource, operation: operation, result: serialize(result)}}
    end
  end

  def manage_order(%{"id" => id, "operation" => operation, "attributes" => attrs}, context) do
    action =
      %{
        "update_status" => :update_status,
        "update_payment" => :update_payment_status,
        "update_fulfillment" => :update_fulfillment
      }[operation]

    with action when is_atom(action) <- action,
         {:ok, order} <- scoped_get(Algoie.Orders.Order, id, context),
         {:ok, updated} <-
           Ash.update(
             order,
             atomize(attrs, order_fields(action)),
             ash_opts(context, action: action)
           ) do
      {:ok, serialize(updated)}
    else
      nil -> {:error, :invalid_operation}
      error -> error
    end
  end

  def create_order(args, context) do
    attrs = %{
      store_id: context.store_id,
      customer_id: Map.get(args, "customer_id"),
      customer: atomize(Map.get(args, "customer", %{}), [:name, :email, :phone]),
      address_id: Map.get(args, "address_id"),
      address:
        atomize(Map.get(args, "address", %{}), [
          :label,
          :recipient_name,
          :phone,
          :address_line1,
          :address_line2,
          :city,
          :area,
          :postal_code,
          :country,
          :default?
        ]),
      variant_quantities:
        Enum.map(Map.get(args, "items", []), &atomize(&1, [:variant_id, :quantity])),
      coupon_code: Map.get(args, "coupon_code"),
      delivery_charge_id: Map.get(args, "delivery_charge_id"),
      delivery_method: Map.get(args, "delivery_method"),
      notes: Map.get(args, "notes")
    }

    case Algoie.Orders.OrderWorkflow.create_order(context.tenant, attrs, context.actor) do
      {:ok, order} -> {:ok, serialize(order)}
      error -> error
    end
  end

  def query_settings(_args, context) do
    case Ash.get(Algoie.Stores.Store, context.store_id, ash_opts(context)) do
      {:ok, store} -> {:ok, serialize(store)}
      error -> error
    end
  end

  def manage_settings(%{"attributes" => attrs}, context) do
    fields = [
      :name,
      :slug,
      :custom_domain,
      :status,
      :email,
      :phone,
      :address,
      :city,
      :country,
      :currency,
      :logo_url,
      :invoice_prefix
    ]

    with {:ok, store} <-
           Ash.get(Algoie.Stores.Store, context.store_id, ash_opts(context)),
         {:ok, updated} <-
           Ash.update(store, atomize(attrs, fields), ash_opts(context)) do
      {:ok, serialize(updated)}
    end
  end

  def deletion_blockers("product", product_id, context) do
    variants =
      Algoie.Products.Variant
      |> filter(product_id == ^product_id and store_id == ^context.store_id)
      |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

    variant_ids = Enum.map(variants, & &1.id)

    %{
      variants: length(variants),
      historical_order_items:
        count_for_ids(Algoie.Orders.OrderLineItem, :variant_id, variant_ids, context),
      images: count_for_product(Algoie.Products.ProductImage, product_id, context),
      categories: count_for_product(Algoie.Products.ProductCategory, product_id, context),
      tags: count_for_product(Algoie.Products.ProductTag, product_id, context),
      collections: count_for_product(Algoie.Products.CollectionProduct, product_id, context)
    }
  end

  def deletion_blockers(_resource, _id, _context), do: %{}

  defp run_query(Algoie.Products.Product, "get", %{"id" => id}, context) do
    policy_context = %{store_id: context.store_id, tenant: context.tenant}

    query =
      Algoie.Products.Product
      |> filter(id == ^id and store_id == ^context.store_id)
      |> load(
        brand: Algoie.Products.Brand |> Ash.Query.set_context(policy_context),
        category: Algoie.Products.Category |> Ash.Query.set_context(policy_context),
        tags: Algoie.Products.Tag |> Ash.Query.set_context(policy_context),
        categories: Algoie.Products.Category |> Ash.Query.set_context(policy_context),
        variants: Algoie.Products.Variant |> Ash.Query.set_context(policy_context)
      )

    case Ash.read_one(query, ash_opts(context)) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, record} -> {:ok, serialize(record)}
      error -> error
    end
  end

  defp run_query(module, "get", %{"id" => id}, context) do
    case scoped_get(module, id, context) do
      {:ok, record} -> {:ok, serialize(record)}
      error -> error
    end
  end

  defp run_query(module, "list", args, context) do
    limit = args |> Map.get("limit", 20) |> min(50)
    search = Map.get(args, "search")

    query =
      module
      |> filter(store_id == ^context.store_id)
      |> then(fn query -> search_query(query, module, search) end)
      |> limit(limit)

    case Ash.read(query, ash_opts(context)) do
      {:ok, records} -> {:ok, Enum.map(records, &serialize/1)}
      error -> error
    end
  end

  defp run_query(_module, _operation, _args, _context), do: {:error, :invalid_arguments}

  defp run_manage(Algoie.Products.Product, fields, "create", args, context) do
    raw = Map.get(args, "attributes", %{})

    Algoie.Repo.transaction(fn ->
      attrs =
        raw
        |> atomize(fields)
        |> Map.drop([:tag_ids, :tags, :category_ids])
        |> Map.put(:store_id, context.store_id)

      with {:ok, product} <- Ash.create(Algoie.Products.Product, attrs, ash_opts(context)),
           :ok <- sync_product_relationships(product.id, raw, context) do
        product
      else
        {:error, reason} -> Algoie.Repo.rollback(reason)
      end
    end)
  end

  defp run_manage(module, fields, "create", args, context) do
    attrs =
      args
      |> Map.get("attributes", %{})
      |> atomize(fields)
      |> put_generated_slug(fields)
      |> Map.put(:store_id, context.store_id)

    Ash.create(module, attrs, ash_opts(context))
  end

  defp run_manage(Algoie.Products.Product, fields, "update", %{"id" => id} = args, context) do
    raw = Map.get(args, "attributes", %{})

    Algoie.Repo.transaction(fn ->
      attrs =
        raw
        |> atomize(fields)
        |> Map.drop([:tag_ids, :tags, :category_ids])

      with {:ok, product} <- scoped_get(Algoie.Products.Product, id, context),
           {:ok, product} <- Ash.update(product, attrs, ash_opts(context)),
           :ok <- sync_product_relationships(product.id, raw, context) do
        product
      else
        {:error, reason} -> Algoie.Repo.rollback(reason)
      end
    end)
  end

  defp run_manage(module, fields, "update", %{"id" => id} = args, context) do
    with {:ok, record} <- scoped_get(module, id, context) do
      Ash.update(record, atomize(Map.get(args, "attributes", %{}), fields), ash_opts(context))
    end
  end

  defp run_manage(Algoie.Products.Product, _fields, "delete", %{"id" => id}, context) do
    blockers = deletion_blockers("product", id, context)

    if blockers.historical_order_items > 0 do
      {:error, {:product_has_order_history, blockers.historical_order_items}}
    else
      Algoie.Repo.transaction(fn ->
        with {:ok, product} <- scoped_get(Algoie.Products.Product, id, context),
             :ok <- destroy_product_dependencies(id, context),
             :ok <- Ash.destroy(product, ash_opts(context)) do
          %{
            id: id,
            deleted: true,
            removed_dependencies: Map.delete(blockers, :historical_order_items)
          }
        else
          {:error, reason} -> Algoie.Repo.rollback(reason)
        end
      end)
    end
  end

  defp run_manage(module, _fields, "delete", %{"id" => id}, context) do
    with {:ok, record} <- scoped_get(module, id, context),
         :ok <- Ash.destroy(record, ash_opts(context)) do
      {:ok, %{id: id, deleted: true}}
    end
  end

  defp run_manage(_module, _fields, _operation, _args, _context), do: {:error, :invalid_arguments}

  defp scoped_get(module, id, context) do
    module
    |> filter(id == ^id and store_id == ^context.store_id)
    |> Ash.read_one(ash_opts(context))
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  defp count_for_product(module, product_id, context) do
    module
    |> filter(product_id == ^product_id)
    |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)
    |> length()
  end

  defp count_for_ids(_module, _field, [], _context), do: 0

  defp count_for_ids(Algoie.Orders.OrderLineItem = module, :variant_id, ids, context) do
    module
    |> filter(variant_id in ^ids)
    |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)
    |> length()
  end

  defp destroy_product_dependencies(product_id, context) do
    modules = [
      Algoie.Products.ProductImage,
      Algoie.Products.ProductCategory,
      Algoie.Products.ProductTag,
      Algoie.Products.CollectionProduct,
      Algoie.Products.Variant
    ]

    Enum.reduce_while(modules, :ok, fn module, :ok ->
      records =
        module
        |> filter(product_id == ^product_id)
        |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

      case Enum.reduce_while(records, :ok, fn record, :ok ->
             case Ash.destroy(record, ash_opts(context)) do
               :ok -> {:cont, :ok}
               {:ok, _record} -> {:cont, :ok}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_product_relationships(product_id, attrs, context) do
    with {:ok, tag_ids} <- requested_tag_ids(attrs, context),
         :ok <-
           maybe_sync_join(
             Algoie.Products.ProductTag,
             :tag_id,
             product_id,
             tag_ids,
             attrs,
             ["tag_ids", "tags"],
             context
           ),
         {:ok, category_ids} <-
           requested_ids(attrs, "category_ids", Algoie.Products.Category, context),
         :ok <-
           maybe_sync_join(
             Algoie.Products.ProductCategory,
             :category_id,
             product_id,
             category_ids,
             attrs,
             ["category_ids"],
             context
           ) do
      :ok
    end
  end

  defp requested_tag_ids(attrs, context) do
    with {:ok, supplied_ids} <- requested_ids(attrs, "tag_ids", Algoie.Products.Tag, context) do
      names = Map.get(attrs, "tags", [])

      Enum.reduce_while(names, {:ok, supplied_ids}, fn name, {:ok, ids} ->
        query =
          Algoie.Products.Tag
          |> filter(store_id == ^context.store_id and name == ^name)

        case Ash.read_one(query, ash_opts(context)) do
          {:ok, nil} ->
            case Ash.create(
                   Algoie.Products.Tag,
                   %{name: name, slug: Slug.slugify(name), store_id: context.store_id},
                   ash_opts(context)
                 ) do
              {:ok, tag} -> {:cont, {:ok, [tag.id | ids]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:ok, tag} ->
            {:cont, {:ok, [tag.id | ids]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, ids} -> {:ok, Enum.uniq(ids)}
        error -> error
      end
    end
  end

  defp requested_ids(attrs, key, module, context) do
    ids = Map.get(attrs, key, [])

    if ids == [] do
      {:ok, []}
    else
      records =
        module
        |> filter(id in ^ids and store_id == ^context.store_id)
        |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

      if length(records) == length(Enum.uniq(ids)),
        do: {:ok, ids},
        else: {:error, "One or more #{String.replace(key, "_", " ")} do not exist in this store"}
    end
  end

  defp maybe_sync_join(module, destination_field, product_id, ids, attrs, keys, context) do
    if Enum.any?(keys, &Map.has_key?(attrs, &1)) do
      existing =
        module
        |> filter(product_id == ^product_id)
        |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

      with :ok <- destroy_records(existing, context) do
        Enum.reduce_while(ids, :ok, fn destination_id, :ok ->
          join_attrs = %{:product_id => product_id, destination_field => destination_id}

          case Ash.create(module, join_attrs, ash_opts(context)) do
            {:ok, _join} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end
    else
      :ok
    end
  end

  defp destroy_records(records, context) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case Ash.destroy(record, ash_opts(context)) do
        :ok -> {:cont, :ok}
        {:ok, _record} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resource_config(resource) do
    @areas
    |> Enum.find_value(fn {_area, config} -> Map.get(config.resources, resource) end)
    |> case do
      nil -> {:error, :unsupported_resource}
      config -> {:ok, config}
    end
  end

  defp atomize(attrs, allowed) do
    Map.new(allowed, fn field ->
      {field, normalize_attribute(field, Map.get(attrs, Atom.to_string(field)))}
    end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_attribute(:option_values, values) when is_list(values) do
    Enum.reduce(values, %{}, fn
      %{"name" => name, "value" => value}, result -> Map.put(result, name, value)
      %{"key" => key, "value" => value}, result -> Map.put(result, key, value)
      %{name: name, value: value}, result -> Map.put(result, name, value)
      _invalid, result -> result
    end)
  end

  defp normalize_attribute(_field, value), do: value

  defp put_generated_slug(attrs, fields) do
    if :slug in fields and is_binary(attrs[:name]) and attrs[:slug] in [nil, ""] do
      Map.put(attrs, :slug, Slug.slugify(attrs.name))
    else
      attrs
    end
  end

  defp ash_opts(context, extra \\ []) do
    Keyword.merge(
      [
        actor: context.actor,
        tenant: context.tenant,
        context: %{store_id: context.store_id, tenant: context.tenant}
      ],
      extra
    )
  end

  defp order_fields(:update_status), do: [:status]
  defp order_fields(:update_payment_status), do: [:payment_status]

  defp order_fields(:update_fulfillment),
    do: [
      :fulfillment_status,
      :courier_provider,
      :courier_consignment_id,
      :tracking_code,
      :courier_payload
    ]

  defp search_query(query, _module, nil), do: query

  defp search_query(query, Algoie.Products.Variant, search),
    do: filter(query, contains(sku, ^search))

  defp search_query(query, Algoie.Customers.Coupon, search),
    do: filter(query, contains(code, ^search))

  defp search_query(query, Algoie.Customers.Customer, search),
    do: filter(query, contains(name, ^search) or contains(email, ^search))

  defp search_query(query, Algoie.Media.MediaAsset, search),
    do: filter(query, contains(filename, ^search) or contains(alt_text, ^search))

  defp search_query(query, _module, search), do: filter(query, contains(name, ^search))

  defp serialize(%_{} = record) do
    record
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__, :calculations, :aggregates, :hashed_password])
    |> Map.reject(fn {key, value} -> internal_key?(key) or match?(%Ash.NotLoaded{}, value) end)
    |> json_safe()
  end

  defp serialize(value), do: json_safe(value)

  defp json_safe(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp json_safe(%Ash.CiString{} = value), do: to_string(value)
  defp json_safe(%DateTime{} = value), do: value
  defp json_safe(%NaiveDateTime{} = value), do: value
  defp json_safe(%Date{} = value), do: value
  defp json_safe(%Time{} = value), do: value

  defp json_safe(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__, :hashed_password])
    |> json_safe()
  end

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, json_safe(item)} end)

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value), do: value

  defp internal_key?(key) when is_atom(key),
    do: key |> Atom.to_string() |> String.starts_with?("__")

  defp internal_key?(key) when is_binary(key), do: String.starts_with?(key, "__")
  defp internal_key?(_key), do: false
end
