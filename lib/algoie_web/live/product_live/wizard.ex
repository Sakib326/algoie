defmodule AlgoieWeb.ProductLive.Wizard do
  use AlgoieWeb, :live_view

  alias Algoie.Products.{Product, Variant, Tag, ProductTag, ProductCategory, ProductImage}
  alias Algoie.Media.MediaAsset
  alias Algoie.AI.FormSuggestions
  alias Algoie.PlatformAISettings
  alias Algoie.Products.VariantGenerator

  require Ash.Query

  @steps ~w(basic category attributes pricing images seo review)
  @boolean_fields ~w(track_inventory? featured is_new variant_price_differs)

  @impl true
  def mount(params, _session, socket) do
    brands = list_related(socket, Algoie.Products.Brand)
    categories = list_related(socket, Algoie.Products.Category)
    tag_suggestions = load_tag_suggestions(socket)
    attribute_name_suggestions = load_attribute_name_suggestions(socket)

    socket =
      socket
      |> assign(:active, :products)
      |> assign(:brands, brands)
      |> assign(:categories, categories)
      |> assign(:brand_map, Map.new(brands, &{&1.id, &1.name}))
      |> assign(:category_map, Map.new(categories, &{&1.id, &1.name}))
      |> assign(:tag_suggestions, tag_suggestions)
      |> assign(:attribute_name_suggestions, attribute_name_suggestions)
      |> assign(:step, 0)
      |> assign(:total_steps, length(@steps))
      |> assign(:step_names, @steps)
      |> assign(:errors, [])
      |> assign(:ai_suggestions, %{})
      |> assign(:ai_loading, false)
      |> assign(
        :ai_enabled,
        "ai.use" in socket.assigns.store_permissions and
          PlatformAISettings.configured?(PlatformAISettings.get())
      )

    socket =
      case params do
        %{"id" => id} -> mount_edit(socket, id)
        _ -> mount_new(socket)
      end

    {:ok, socket}
  end

  defp load_tag_suggestions(socket) do
    socket
    |> list_related(Tag)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp load_attribute_name_suggestions(socket) do
    socket
    |> list_related(Product)
    |> Enum.flat_map(fn product -> Map.keys(product.attribute_definitions || %{}) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp mount_new(socket) do
    socket
    |> assign(:mode, :new)
    |> assign(:page_title, "Create Product")
    |> assign(:product, nil)
    |> assign(:simple_variant_id, nil)
    |> assign(:wizard_data, default_wizard_data())
    |> assign(:generated_variants, [])
  end

  defp mount_edit(socket, id) do
    opts = AlgoieWeb.Scope.opts(socket)

    case Ash.get(Product, id, opts) do
      {:ok, product} ->
        variants = load_variants(socket, product)
        tags = load_tags(socket, product)
        category_ids = load_category_ids(socket, product)

        {wizard_data, generated_variants} =
          build_edit_state(socket, product, variants, tags, category_ids)

        simple_variant_id =
          if product.product_type == :simple do
            case List.first(variants) do
              nil -> nil
              variant -> variant.id
            end
          end

        socket
        |> assign(:mode, :edit)
        |> assign(:page_title, "Edit Product")
        |> assign(:product, product)
        |> assign(:simple_variant_id, simple_variant_id)
        |> assign(:wizard_data, wizard_data)
        |> assign(:generated_variants, generated_variants)

      _ ->
        socket
        |> put_flash(:error, "Product not found")
        |> mount_new()
    end
  end

  defp default_wizard_data do
    %{
      "name" => "",
      "slug" => "",
      "slug_manually_edited" => false,
      "description" => "",
      "product_type" => "simple",
      "category_id" => nil,
      "category_ids" => [],
      "brand_id" => nil,
      "featured" => false,
      "is_new" => false,
      "attribute_definitions" => %{},
      "sku" => "",
      "price" => "",
      "cost_price" => "",
      "compare_at_price" => "",
      "stock" => "0",
      "low_stock_threshold" => "10",
      "track_inventory?" => true,
      "barcode" => "",
      "variant_price_differs" => false,
      "meta_title" => "",
      "meta_description" => "",
      "tags" => [],
      "tag_input" => "",
      "product_image_urls" => []
    }
  end

  defp load_variants(socket, product) do
    Variant
    |> Ash.Query.filter(product_id == ^product.id)
    |> Ash.Query.sort(:position)
    |> Ash.read(AlgoieWeb.Scope.opts(socket))
    |> case do
      {:ok, variants} -> variants
      _ -> []
    end
  end

  defp load_tags(socket, product) do
    tag_query =
      Tag
      |> Ash.Query.set_context(%{
        store_id: socket.assigns.store_id,
        tenant: socket.assigns.tenant
      })

    ProductTag
    |> Ash.Query.filter(product_id == ^product.id)
    |> Ash.Query.load(tag: tag_query)
    |> Ash.read(AlgoieWeb.Scope.opts(socket))
    |> case do
      {:ok, product_tags} -> Enum.map(product_tags, & &1.tag.name)
      _ -> []
    end
  end

  defp load_category_ids(socket, product) do
    ProductCategory
    |> Ash.Query.filter(product_id == ^product.id)
    |> Ash.read(AlgoieWeb.Scope.opts(socket))
    |> case do
      {:ok, product_categories} -> Enum.map(product_categories, & &1.category_id)
      _ -> []
    end
  end

  defp load_image_urls(socket, product_id, variant_id) do
    opts = AlgoieWeb.Scope.opts(socket) |> Keyword.put(:authorize?, false)

    query =
      case variant_id do
        nil ->
          ProductImage
          |> Ash.Query.filter(product_id == ^product_id and is_nil(variant_id))

        id ->
          ProductImage
          |> Ash.Query.filter(product_id == ^product_id and variant_id == ^id)
      end

    query
    |> Ash.Query.sort(:position)
    |> Ash.Query.load(:media_asset)
    |> Ash.read(opts)
    |> case do
      {:ok, images} ->
        urls =
          Enum.map(images, fn img ->
            if img.media_asset do
              img.media_asset.url
            else
              "MISSING MEDIA ASSET"
            end
          end)

        IO.inspect(urls, label: "LOADED IMAGE URLS FOR #{variant_id || "PRODUCT"}")
        urls

      err ->
        IO.inspect(err, label: "FAILED TO LOAD IMAGE URLS FOR #{variant_id || "PRODUCT"}")
        []
    end
  end

  defp build_edit_state(socket, product, variants, tags, category_ids) do
    first_variant = List.first(variants)

    wizard_data = %{
      "name" => product.name,
      "slug" => product.slug || "",
      "slug_manually_edited" => true,
      "description" => product.description || "",
      "product_type" => to_string(product.product_type),
      "category_id" => product.category_id,
      "category_ids" => category_ids,
      "brand_id" => product.brand_id,
      "featured" => product.featured,
      "is_new" => product.is_new,
      "attribute_definitions" => product.attribute_definitions || %{},
      "sku" => (first_variant && first_variant.sku) || "",
      "price" => decimal_to_string(first_variant && first_variant.price),
      "cost_price" => decimal_to_string(first_variant && first_variant.cost_price),
      "compare_at_price" => decimal_to_string(first_variant && first_variant.compare_at_price),
      "stock" => to_string((first_variant && first_variant.stock) || 0),
      "low_stock_threshold" =>
        to_string((first_variant && first_variant.low_stock_threshold) || 10),
      "track_inventory?" => if(first_variant, do: first_variant.track_inventory?, else: true),
      "barcode" => (first_variant && first_variant.barcode) || "",
      "variant_price_differs" => product.product_type == :variable,
      "meta_title" => product.meta_title || "",
      "meta_description" => product.meta_description || "",
      "tags" => tags,
      "tag_input" => "",
      "product_image_urls" => load_image_urls(socket, product.id, nil)
    }

    generated_variants =
      if product.product_type == :variable do
        Enum.map(variants, fn v ->
          %{
            "id" => v.id,
            "sku" => v.sku,
            "price" => decimal_to_string(v.price),
            "cost_price" => decimal_to_string(v.cost_price),
            "compare_at_price" => decimal_to_string(v.compare_at_price),
            "stock" => to_string(v.stock),
            "low_stock_threshold" => to_string(v.low_stock_threshold),
            "track_inventory?" => v.track_inventory?,
            "barcode" => v.barcode,
            "option_values" => v.option_values,
            "position" => v.position,
            "image_urls" => load_image_urls(socket, product.id, v.id)
          }
        end)
      else
        []
      end

    {wizard_data, generated_variants}
  end

  defp decimal_to_string(nil), do: ""
  defp decimal_to_string(%Decimal{} = d), do: Decimal.to_string(d)

  defp simple_sku(data) do
    case data["sku"] do
      sku when is_binary(sku) and sku != "" -> sku
      _ -> data["slug"] || Ecto.UUID.generate()
    end
  end

  @impl true
  def handle_params(%{"step" => step_str}, _url, socket) do
    step = String.to_integer(step_str)

    if step in 0..(socket.assigns.total_steps - 1) do
      {:noreply, assign(socket, :step, step)}
    else
      {:noreply, assign(socket, :step, 0)}
    end
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("suggest_fields", _params, %{assigns: %{mode: :edit}} = socket) do
    context = %{actor: socket.assigns.current_user, store_id: socket.assigns.store_id}
    values = socket.assigns.wizard_data

    {:noreply,
     socket
     |> assign(:ai_loading, true)
     |> start_async(:product_suggestions, fn ->
       FormSuggestions.suggest("product", values, context)
     end)}
  end

  def handle_event("suggest_fields", _params, socket), do: {:noreply, socket}

  def handle_event("update_field", %{"_target" => [field]} = params, socket) do
    # When phx-change is on an individual input, the payload may use the "value" key
    # instead of the field name key.
    value =
      case Map.fetch(params, field) do
        {:ok, val} -> val
        :error -> Map.get(params, "value", "")
      end

    # Cast known boolean fields back to booleans so downstream `!` and `if` work correctly.
    value = if field in @boolean_fields, do: to_boolean(value), else: value

    wizard_data = Map.put(socket.assigns.wizard_data, field, value)

    wizard_data =
      cond do
        field == "name" && !wizard_data["slug_manually_edited"] ->
          Map.put(wizard_data, "slug", Slug.slugify(value))

        field == "slug" ->
          Map.put(wizard_data, "slug_manually_edited", true)

        true ->
          wizard_data
      end

    {:noreply, assign(socket, :wizard_data, wizard_data)}
  end

  def handle_event("toggle_field", %{"field" => field}, socket) do
    wizard_data =
      Map.update!(socket.assigns.wizard_data, field, fn val -> !to_boolean(val) end)

    {:noreply, assign(socket, :wizard_data, wizard_data)}
  end

  def handle_event("toggle_category", %{"category" => category_id}, socket) do
    category_ids = socket.assigns.wizard_data["category_ids"]

    category_ids =
      if category_id in category_ids do
        List.delete(category_ids, category_id)
      else
        [category_id | category_ids]
      end

    wizard_data = Map.put(socket.assigns.wizard_data, "category_ids", category_ids)
    {:noreply, assign(socket, :wizard_data, wizard_data)}
  end

  def handle_event("next_step", _params, socket) do
    case validate_step(socket.assigns.step, socket.assigns.wizard_data) do
      :ok ->
        next_step =
          socket.assigns.step
          |> Kernel.+(1)
          |> min(socket.assigns.total_steps - 1)
          |> adjust_step_for_product_type(socket.assigns.wizard_data, :forward)

        socket =
          socket
          |> assign(:step, next_step)
          |> assign(:errors, [])

        socket =
          if next_step == 3 && socket.assigns.generated_variants == [] &&
               socket.assigns.wizard_data["product_type"] == "variable" do
            generate_variants(socket)
          else
            socket
          end

        {:noreply, socket}

      {:error, errors} ->
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  def handle_event("prev_step", _params, socket) do
    prev_step =
      socket.assigns.step
      |> Kernel.-(1)
      |> max(0)
      |> adjust_step_for_product_type(socket.assigns.wizard_data, :backward)

    {:noreply, socket |> assign(:step, prev_step) |> assign(:errors, [])}
  end

  def handle_event("go_to_step", %{"step" => step_str}, socket) do
    step = String.to_integer(step_str)

    socket =
      socket
      |> assign(:step, step)
      |> assign(:errors, [])

    socket =
      if step == 3 && socket.assigns.generated_variants == [] &&
           socket.assigns.wizard_data["product_type"] == "variable" do
        generate_variants(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event(
        "add_attribute",
        %{"attr_name" => attr_name, "attr_values" => values_str},
        socket
      ) do
    values =
      values_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if attr_name != "" && values != [] do
      definitions = socket.assigns.wizard_data["attribute_definitions"]
      definitions = Map.put(definitions, attr_name, values)

      wizard_data = Map.put(socket.assigns.wizard_data, "attribute_definitions", definitions)

      {:noreply,
       socket
       |> assign(:wizard_data, wizard_data)
       |> assign(:generated_variants, [])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_attribute", %{"attr" => attr_name}, socket) do
    definitions = Map.delete(socket.assigns.wizard_data["attribute_definitions"], attr_name)
    wizard_data = Map.put(socket.assigns.wizard_data, "attribute_definitions", definitions)

    {:noreply,
     socket
     |> assign(:wizard_data, wizard_data)
     |> assign(:generated_variants, [])}
  end

  def handle_event("generate_variants", _params, socket) do
    {:noreply, generate_variants(socket)}
  end

  def handle_event("update_variant", %{"_target" => ["variant", idx_str, field]} = params, socket) do
    idx = String.to_integer(idx_str)

    value =
      case get_in(params, ["variant", idx_str, field]) do
        nil -> Map.get(params, "value", "")
        val -> val
      end

    variants =
      List.update_at(socket.assigns.generated_variants, idx, &Map.put(&1, field, value))

    {:noreply, assign(socket, :generated_variants, variants)}
  end

  def handle_event("toggle_variant_price_differs", _params, socket) do
    current = socket.assigns.wizard_data["variant_price_differs"]

    wizard_data =
      Map.put(socket.assigns.wizard_data, "variant_price_differs", !to_boolean(current))

    {:noreply, assign(socket, :wizard_data, wizard_data)}
  end

  def handle_event("toggle_variant_track_inventory", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    variants =
      List.update_at(socket.assigns.generated_variants, idx, fn v ->
        Map.put(v, "track_inventory?", !to_boolean(Map.get(v, "track_inventory?", true)))
      end)

    {:noreply, assign(socket, :generated_variants, variants)}
  end

  def handle_event("add_tag", %{"tag" => tag_name}, socket) do
    tag_name = String.trim(tag_name)

    if tag_name != "" && tag_name not in socket.assigns.wizard_data["tags"] do
      tags = socket.assigns.wizard_data["tags"] ++ [tag_name]

      wizard_data =
        socket.assigns.wizard_data
        |> Map.put("tags", tags)
        |> Map.put("tag_input", "")

      {:noreply, assign(socket, :wizard_data, wizard_data)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_tag", %{"tag" => tag_name}, socket) do
    tags = List.delete(socket.assigns.wizard_data["tags"], tag_name)
    wizard_data = Map.put(socket.assigns.wizard_data, "tags", tags)
    {:noreply, assign(socket, :wizard_data, wizard_data)}
  end

  def handle_event("publish", %{"status" => status}, socket) do
    case validate_step(socket.assigns.step, socket.assigns.wizard_data) do
      :ok ->
        create_product(socket, status)

      {:error, errors} ->
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  @impl true
  def handle_async(:product_suggestions, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, socket |> assign(:ai_suggestions, suggestions) |> assign(:ai_loading, false)}
  end

  def handle_async(:product_suggestions, _result, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, false)
     |> put_flash(:error, "AI suggestions could not be generated. Please try again.")}
  end

  @impl true
  def handle_info({:media_manager_updated, "product-images", selected_urls}, socket) do
    wizard_data = Map.put(socket.assigns.wizard_data, "product_image_urls", selected_urls)
    {:noreply, assign(socket, :wizard_data, wizard_data)}
  end

  def handle_info({:media_manager_updated, "variant-images-" <> idx_str, selected_urls}, socket) do
    idx = String.to_integer(idx_str)

    variants =
      List.update_at(socket.assigns.generated_variants, idx, fn v ->
        Map.put(v, "image_urls", selected_urls)
      end)

    {:noreply, assign(socket, :generated_variants, variants)}
  end

  defp create_product(socket, status) do
    data = socket.assigns.wizard_data

    product_attrs = %{
      "name" => data["name"],
      "slug" => data["slug"],
      "description" => data["description"],
      "product_type" => data["product_type"],
      "brand_id" => if(data["brand_id"] != "", do: data["brand_id"]),
      "category_id" => if(data["category_id"] != "", do: data["category_id"]),
      "featured" => data["featured"],
      "is_new" => data["is_new"],
      "attribute_definitions" => data["attribute_definitions"],
      "meta_title" => data["meta_title"],
      "meta_description" => data["meta_description"],
      "status" => status
    }

    opts = AlgoieWeb.Scope.opts(socket)

    case socket.assigns.mode do
      :edit -> update_product(socket, product_attrs, opts, data)
      :new -> insert_product(socket, product_attrs, opts, data)
    end
  end

  defp insert_product(socket, product_attrs, opts, data) do
    product_attrs = Map.put(product_attrs, "store_id", socket.assigns.store_id)

    result =
      Algoie.Repo.transaction(fn ->
        with {:ok, product} <- Ash.create(Product, product_attrs, opts),
             {created_variants, []} <- create_variants(product, socket, data),
             {:ok, tag_notifications} <- create_tags(product, socket, data),
             {:ok, category_notifications} <- create_categories(product, socket, data) do
          create_images(product, socket, data, created_variants)
          {product, tag_notifications ++ category_notifications}
        else
          {_variants, errors} when is_list(errors) ->
            Algoie.Repo.rollback({:variant_errors, errors})

          {:error, error} ->
            Algoie.Repo.rollback(error)
        end
      end)

    case result do
      {:ok, {_product, notifications}} ->
        Ash.Notifier.notify(notifications)

        {:noreply,
         socket
         |> put_flash(:info, "Product and inventory created successfully")
         |> push_navigate(to: ~p"/dashboard/products")}

      {:error, {:variant_errors, errors}} ->
        {:noreply, assign(socket, :errors, errors)}

      {:error, error} ->
        {:noreply, assign(socket, :errors, format_changeset_errors(error))}
    end
  end

  defp update_product(socket, product_attrs, opts, data) do
    result =
      Algoie.Repo.transaction(fn ->
        with {:ok, product} <- Ash.update(socket.assigns.product, product_attrs, opts),
             {_updated, []} <- update_variants(socket, data, opts),
             {:ok, tag_notifications} <- sync_tags(product, socket, data, opts),
             {:ok, category_notifications} <- sync_categories(product, socket, data, opts) do
          sync_images(product, socket, data, opts)
          {product, tag_notifications ++ category_notifications}
        else
          {_variants, errors} when is_list(errors) ->
            Algoie.Repo.rollback({:variant_errors, errors})

          {:error, error} ->
            Algoie.Repo.rollback(error)
        end
      end)

    case result do
      {:ok, {_product, notifications}} ->
        Ash.Notifier.notify(notifications)

        {:noreply,
         socket
         |> put_flash(:info, "Product, pricing, and inventory updated successfully")
         |> push_navigate(to: ~p"/dashboard/products")}

      {:error, {:variant_errors, errors}} ->
        {:noreply, assign(socket, :errors, errors)}

      {:error, error} ->
        {:noreply, assign(socket, :errors, format_changeset_errors(error))}
    end
  end

  defp create_variants(product, socket, data) do
    opts = AlgoieWeb.Scope.opts(socket)

    variants_to_create =
      if data["product_type"] == "simple" do
        [
          %{
            "product_id" => product.id,
            "store_id" => socket.assigns.store_id,
            "sku" => simple_sku(data),
            "price" => data["price"],
            "cost_price" => if(data["cost_price"] not in ["", nil], do: data["cost_price"]),
            "compare_at_price" =>
              if(data["compare_at_price"] not in ["", nil], do: data["compare_at_price"]),
            "stock" =>
              if(data["track_inventory?"] && data["stock"] not in ["", nil],
                do: data["stock"],
                else: 0
              ),
            "low_stock_threshold" =>
              if(data["low_stock_threshold"] not in ["", nil], do: data["low_stock_threshold"]),
            "track_inventory?" => data["track_inventory?"],
            "barcode" => if(data["barcode"] not in ["", nil], do: data["barcode"]),
            "option_values" => %{},
            "position" => 0
          }
        ]
      else
        Enum.map(socket.assigns.generated_variants, fn v ->
          effective_price =
            if data["variant_price_differs"],
              do: v["price"],
              else: data["price"]

          effective_cost_price =
            if data["variant_price_differs"],
              do: v["cost_price"],
              else: data["cost_price"]

          effective_compare_at_price =
            if data["variant_price_differs"],
              do: v["compare_at_price"],
              else: data["compare_at_price"]

          %{
            "product_id" => product.id,
            "store_id" => socket.assigns.store_id,
            "sku" => v["sku"],
            "price" => effective_price,
            "cost_price" => if(effective_cost_price not in ["", nil], do: effective_cost_price),
            "compare_at_price" =>
              if(effective_compare_at_price not in ["", nil], do: effective_compare_at_price),
            "barcode" => if(v["barcode"] not in ["", nil], do: v["barcode"]),
            "stock" =>
              if(Map.get(v, "track_inventory?", true) && v["stock"] not in ["", nil],
                do: v["stock"],
                else: 0
              ),
            "low_stock_threshold" =>
              if(data["low_stock_threshold"] not in ["", nil], do: data["low_stock_threshold"]),
            "track_inventory?" => Map.get(v, "track_inventory?", true),
            "option_values" => v["option_values"],
            "position" => v["position"]
          }
        end)
      end

    results =
      Enum.map(variants_to_create, fn attrs ->
        case Ash.create(Variant, attrs, opts) do
          {:ok, variant} -> {:ok, variant}
          {:error, error} -> {:error, error}
        end
      end)

    created =
      Enum.map(results, fn
        {:ok, variant} -> variant
        {:error, _} -> nil
      end)

    errors =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.flat_map(fn {:error, err} -> format_changeset_errors(err) end)

    {created, errors}
  end

  defp update_variants(socket, data, opts) do
    results =
      if data["product_type"] == "simple" do
        [update_simple_variant(socket, data, opts)]
      else
        Enum.map(socket.assigns.generated_variants, fn v ->
          effective_price =
            if data["variant_price_differs"],
              do: v["price"],
              else: data["price"]

          effective_cost_price =
            if data["variant_price_differs"],
              do: v["cost_price"],
              else: data["cost_price"]

          effective_compare_at_price =
            if data["variant_price_differs"],
              do: v["compare_at_price"],
              else: data["compare_at_price"]

          if is_binary(v["id"]) do
            payload = %{
              "sku" => v["sku"],
              "price" => effective_price,
              "cost_price" => if(effective_cost_price not in ["", nil], do: effective_cost_price),
              "compare_at_price" =>
                if(effective_compare_at_price not in ["", nil], do: effective_compare_at_price),
              "stock" =>
                if(Map.get(v, "track_inventory?", true) && v["stock"] not in ["", nil],
                  do: v["stock"],
                  else: 0
                ),
              "track_inventory?" => Map.get(v, "track_inventory?", true),
              "barcode" => if(v["barcode"] not in ["", nil], do: v["barcode"], else: nil)
            }

            case Ash.get(Variant, v["id"], opts) do
              {:ok, variant} ->
                Ash.update(variant, payload, opts)

              error ->
                error
            end
          else
            # Newly generated variant during edit session
            payload = %{
              "product_id" => socket.assigns.product.id,
              "store_id" => socket.assigns.store_id,
              "sku" => v["sku"],
              "price" => effective_price,
              "cost_price" => if(effective_cost_price not in ["", nil], do: effective_cost_price),
              "compare_at_price" =>
                if(effective_compare_at_price not in ["", nil], do: effective_compare_at_price),
              "stock" =>
                if(Map.get(v, "track_inventory?", true) && v["stock"] not in ["", nil],
                  do: v["stock"],
                  else: 0
                ),
              "low_stock_threshold" =>
                if(data["low_stock_threshold"] not in ["", nil], do: data["low_stock_threshold"]),
              "track_inventory?" => Map.get(v, "track_inventory?", true),
              "barcode" => if(v["barcode"] not in ["", nil], do: v["barcode"]),
              "option_values" => v["option_values"],
              "position" => v["position"] || 0
            }

            Ash.create(Variant, payload, opts)
          end
        end)
      end

    updated =
      Enum.map(results, fn
        {:ok, variant} -> variant
        _ -> nil
      end)

    errors =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.flat_map(fn {:error, err} -> format_changeset_errors(err) end)

    {updated, errors}
  end

  defp update_simple_variant(socket, data, opts) do
    with id when is_binary(id) <- socket.assigns.simple_variant_id,
         {:ok, variant} <- Ash.get(Variant, id, opts) do
      payload = %{
        "sku" => simple_sku(data),
        "price" => data["price"],
        "cost_price" =>
          if(data["cost_price"] not in ["", nil], do: data["cost_price"], else: nil),
        "compare_at_price" =>
          if(data["compare_at_price"] not in ["", nil], do: data["compare_at_price"], else: nil),
        "stock" =>
          if(data["track_inventory?"] && data["stock"] not in ["", nil],
            do: data["stock"],
            else: 0
          ),
        "low_stock_threshold" =>
          if(data["low_stock_threshold"] not in ["", nil],
            do: data["low_stock_threshold"],
            else: nil
          ),
        "track_inventory?" => data["track_inventory?"],
        "barcode" => if(data["barcode"] not in ["", nil], do: data["barcode"], else: nil)
      }

      Ash.update(variant, payload, opts)
    else
      _ ->
        Ash.create(
          Variant,
          Map.merge(payload_for_simple_variant(data), %{
            "product_id" => socket.assigns.product.id,
            "store_id" => socket.assigns.store_id,
            "option_values" => %{},
            "position" => 0
          }),
          opts
        )
    end
  end

  defp payload_for_simple_variant(data) do
    %{
      "sku" => simple_sku(data),
      "price" => data["price"],
      "cost_price" => if(data["cost_price"] not in ["", nil], do: data["cost_price"]),
      "compare_at_price" =>
        if(data["compare_at_price"] not in ["", nil], do: data["compare_at_price"]),
      "stock" =>
        if(data["track_inventory?"] && data["stock"] not in ["", nil],
          do: data["stock"],
          else: 0
        ),
      "low_stock_threshold" =>
        if(data["low_stock_threshold"] not in ["", nil], do: data["low_stock_threshold"]),
      "track_inventory?" => data["track_inventory?"],
      "barcode" => if(data["barcode"] not in ["", nil], do: data["barcode"])
    }
  end

  defp sync_tags(product, socket, data, opts) do
    with {:ok, product_tags} <-
           ProductTag |> Ash.Query.filter(product_id == ^product.id) |> Ash.read(opts),
         {:ok, destroy_notifications} <- destroy_with_notifications(product_tags, opts),
         {:ok, create_notifications} <- create_tags(product, socket, data) do
      {:ok, destroy_notifications ++ create_notifications}
    end
  end

  defp create_tags(product, socket, data) do
    opts = AlgoieWeb.Scope.opts(socket)

    tags =
      (data["tags"] || [])
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    Enum.reduce_while(tags, {:ok, []}, fn tag_name, {:ok, notifications} ->
      slug = Slug.slugify(tag_name)

      with {:ok, tag, tag_notifications} <- find_or_create_tag(tag_name, slug, socket, opts),
           {:ok, _join, join_notifications} <-
             Ash.create(
               ProductTag,
               %{product_id: product.id, tag_id: tag.id},
               Keyword.put(opts, :return_notifications?, true)
             ) do
        {:cont, {:ok, notifications ++ tag_notifications ++ join_notifications}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_categories(product, socket, data) do
    opts = AlgoieWeb.Scope.opts(socket)

    category_ids =
      (data["category_ids"] || [])
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Enum.reduce_while(category_ids, {:ok, []}, fn category_id, {:ok, notifications} ->
      case Ash.create(
             ProductCategory,
             %{product_id: product.id, category_id: category_id},
             Keyword.put(opts, :return_notifications?, true)
           ) do
        {:ok, _join, new_notifications} ->
          {:cont, {:ok, notifications ++ new_notifications}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_categories(product, socket, data, opts) do
    with {:ok, product_categories} <-
           ProductCategory |> Ash.Query.filter(product_id == ^product.id) |> Ash.read(opts),
         {:ok, destroy_notifications} <- destroy_with_notifications(product_categories, opts),
         {:ok, create_notifications} <- create_categories(product, socket, data) do
      {:ok, destroy_notifications ++ create_notifications}
    end
  end

  defp find_or_create_tag(tag_name, slug, socket, opts) do
    case Ash.get(Tag, [slug: slug, store_id: socket.assigns.store_id], opts) do
      {:ok, tag} ->
        {:ok, tag, []}

      _ ->
        Ash.create(
          Tag,
          %{name: tag_name, slug: slug, store_id: socket.assigns.store_id},
          Keyword.put(opts, :return_notifications?, true)
        )
    end
  end

  defp destroy_with_notifications(records, opts) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, notifications} ->
      case Ash.destroy(record, Keyword.put(opts, :return_notifications?, true)) do
        {:ok, new_notifications} -> {:cont, {:ok, notifications ++ new_notifications}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_images(product, socket, data, created_variants) do
    opts = AlgoieWeb.Scope.opts(socket)

    create_image_set(product.id, nil, data["product_image_urls"], opts)

    if data["product_type"] == "variable" do
      socket.assigns.generated_variants
      |> Enum.zip(created_variants)
      |> Enum.each(fn {v, variant} ->
        if variant do
          create_image_set(product.id, variant.id, v["image_urls"] || [], opts)
        end
      end)
    end
  end

  defp sync_images(product, socket, data, opts) do
    destroy_image_set(product.id, nil, opts)
    create_image_set(product.id, nil, data["product_image_urls"], opts)

    if data["product_type"] == "variable" do
      Enum.each(socket.assigns.generated_variants, fn v ->
        if id = v["id"] do
          destroy_image_set(product.id, id, opts)
          create_image_set(product.id, id, v["image_urls"] || [], opts)
        end
      end)
    end
  end

  defp create_image_set(product_id, variant_id, urls, opts) do
    urls
    |> Enum.with_index()
    |> Enum.each(fn {url, position} ->
      case find_media_asset(url, opts) do
        {:ok, asset} ->
          Ash.create(
            ProductImage,
            %{
              product_id: product_id,
              variant_id: variant_id,
              media_asset_id: asset.id,
              position: position
            },
            opts
          )

        :error ->
          :ok
      end
    end)
  end

  defp destroy_image_set(product_id, nil, opts) do
    ProductImage
    |> Ash.Query.filter(product_id == ^product_id and is_nil(variant_id))
    |> Ash.read(opts)
    |> case do
      {:ok, images} -> Enum.each(images, &Ash.destroy(&1, opts))
      _ -> :ok
    end
  end

  defp destroy_image_set(product_id, variant_id, opts) do
    ProductImage
    |> Ash.Query.filter(product_id == ^product_id and variant_id == ^variant_id)
    |> Ash.read(opts)
    |> case do
      {:ok, images} -> Enum.each(images, &Ash.destroy(&1, opts))
      _ -> :ok
    end
  end

  defp find_media_asset(url, opts) do
    opts = Keyword.put(opts, :page, false)

    MediaAsset
    |> Ash.Query.filter(url == ^url)
    |> Ash.Query.limit(1)
    |> Ash.read(opts)
    |> case do
      {:ok, [asset | _]} -> {:ok, asset}
      _ -> :error
    end
  end

  # The Attributes step (index 2) only applies to variable products.
  # Simple products skip straight between Category (1) and Pricing (3).
  defp adjust_step_for_product_type(2, %{"product_type" => "simple"}, :forward), do: 3
  defp adjust_step_for_product_type(2, %{"product_type" => "simple"}, :backward), do: 1
  defp adjust_step_for_product_type(step, _data, _direction), do: step

  defp generate_variants(socket) do
    data = socket.assigns.wizard_data
    definitions = data["attribute_definitions"]

    variants =
      definitions
      |> VariantGenerator.generate()
      |> Enum.with_index()
      |> Enum.map(fn {option_values, idx} ->
        %{
          "sku" => VariantGenerator.generate_sku(data["slug"] || "product", option_values),
          "price" => data["price"] || "",
          "cost_price" => data["cost_price"] || "",
          "compare_at_price" => data["compare_at_price"] || "",
          "stock" => data["stock"] || "0",
          "barcode" => "",
          "track_inventory?" => data["track_inventory?"],
          "option_values" => option_values,
          "position" => idx,
          "image_urls" => []
        }
      end)

    assign(socket, :generated_variants, variants)
  end

  defp validate_step(0, data) do
    errors = []
    errors = if data["name"] == "", do: ["Product name is required" | errors], else: errors

    errors =
      if String.length(data["name"]) > 255,
        do: ["Product name must be 255 characters or fewer" | errors],
        else: errors

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp validate_step(2, data) do
    errors = []

    errors =
      if data["product_type"] == "variable" && map_size(data["attribute_definitions"]) == 0 do
        ["Variable products must define at least one attribute" | errors]
      else
        errors
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp validate_step(3, data) do
    errors = validate_pricing(data) ++ validate_inventory(data)
    if errors == [], do: :ok, else: {:error, errors}
  end

  defp validate_step(_step, _data), do: :ok

  defp validate_pricing(data) do
    if data["product_type"] == "variable" && data["variant_price_differs"] do
      # Each variant is validated by the Variant resource before the transaction commits.
      []
    else
      validate_decimal_price(data["price"], "Selling price") ++
        validate_optional_money(data["cost_price"], "Cost price") ++
        validate_compare_price(data["compare_at_price"], data["price"], "Compare-at price")
    end
  end

  defp validate_inventory(data) do
    if to_boolean(data["track_inventory?"]) do
      validate_non_negative_integer(data["stock"], "Stock quantity") ++
        validate_non_negative_integer(data["low_stock_threshold"], "Low stock alert")
    else
      []
    end
  end

  defp validate_optional_money(value, _label) when value in [nil, ""], do: []

  defp validate_optional_money(value, label) do
    case Decimal.parse(to_string(value)) do
      {decimal, ""} ->
        if Decimal.negative?(decimal), do: ["#{label} cannot be negative"], else: []

      _ ->
        ["#{label} must be a valid amount"]
    end
  end

  defp validate_compare_price(value, _price, _label) when value in [nil, ""], do: []

  defp validate_compare_price(value, price, label) do
    with {compare, ""} <- Decimal.parse(to_string(value)),
         {selling, ""} <- Decimal.parse(to_string(price)),
         :gt <- Decimal.compare(compare, selling) do
      []
    else
      _ -> ["#{label} must be greater than the selling price"]
    end
  end

  defp validate_non_negative_integer(value, label) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} when integer >= 0 -> []
      _ -> ["#{label} must be a whole number of zero or more"]
    end
  end

  defp validate_decimal_price(value, label) do
    cond do
      value in ["", nil] ->
        ["Valid #{label} is required"]

      true ->
        case Decimal.parse(value) do
          {parsed, ""} ->
            if Decimal.compare(parsed, Decimal.new(0)) != :gt,
              do: ["#{label} must be greater than 0"],
              else: []

          _ ->
            ["Valid #{label} is required"]
        end
    end
  end

  defp format_changeset_errors(error_or_changeset) do
    error_or_changeset
    |> extract_errors()
    |> Enum.map(fn error ->
      case error do
        %{field: field} when not is_nil(field) -> "#{field}: #{Exception.message(error)}"
        _ -> Exception.message(error)
      end
    end)
  end

  defp extract_errors(%{errors: errors}) when is_list(errors) do
    Enum.flat_map(errors, &extract_errors/1)
  end

  defp extract_errors(error), do: [error]

  # Safely coerce a value to boolean. Handles true/false, "true"/"false", and nil.
  defp to_boolean(true), do: true
  defp to_boolean(false), do: false
  defp to_boolean("true"), do: true
  defp to_boolean("false"), do: false
  defp to_boolean(nil), do: false
  defp to_boolean(_), do: false

  defp list_related(socket, resource) do
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, false)

    case Ash.read(resource, opts) do
      {:ok, records} -> records
      _ -> []
    end
  end

  defp step_label(0), do: "Basic Info"
  defp step_label(1), do: "Category & Brand"
  defp step_label(2), do: "Attributes"
  defp step_label(3), do: "Pricing"
  defp step_label(4), do: "Images"
  defp step_label(5), do: "SEO"
  defp step_label(6), do: "Review"
end
