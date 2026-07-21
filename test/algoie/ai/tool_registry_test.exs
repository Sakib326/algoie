defmodule Algoie.AI.ToolRegistryTest do
  use ExUnit.Case, async: false

  alias Algoie.AI.{ToolExecutor, ToolRegistry}

  defmodule ReadTool do
    @behaviour Algoie.AI.Tool

    @impl true
    def definition do
      %{
        id: "test.read",
        version: 1,
        risk: :read_only,
        permissions: ["reports.view"],
        input_schema: %{"type" => "object", "required" => ["query"]},
        handler: fn arguments, context ->
          {:ok, %{query: arguments["query"], store_id: context.store_id}}
        end
      }
    end
  end

  defmodule WriteTool do
    @behaviour Algoie.AI.Tool

    @impl true
    def definition do
      %{
        id: "test.write",
        version: 1,
        risk: :write,
        permissions: ["catalog.manage"],
        input_schema: %{"type" => "object"},
        handler: fn _arguments, _context -> {:ok, %{}} end
      }
    end
  end

  setup do
    previous = Application.get_env(:algoie, :ai_tools)
    Application.put_env(:algoie, :ai_tools, [ReadTool, WriteTool])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:algoie, :ai_tools, previous),
        else: Application.delete_env(:algoie, :ai_tools)
    end)

    :ok
  end

  test "only exposes schemas allowed by the current permission set" do
    assert [%{function: %{name: "test.read"}}] = ToolRegistry.provider_schemas(["reports.view"])
    assert [] = ToolRegistry.provider_schemas([])
  end

  test "requires a scoped execution context and approval for writes" do
    context = %{
      actor: %{id: "user"},
      tenant: "tenant_1",
      store_id: "store_1",
      permissions: ["reports.view", "catalog.manage"]
    }

    assert {:ok, %{query: "revenue", store_id: "store_1"}} =
             ToolExecutor.execute("test.read", %{"query" => "revenue"}, context)

    assert {:approval_required, %{tool_id: "test.write", risk: :write}} =
             ToolExecutor.execute("test.write", %{}, context)

    assert {:error, :invalid_execution_context} =
             ToolExecutor.execute("test.read", %{"query" => "revenue"}, %{})
  end
end
