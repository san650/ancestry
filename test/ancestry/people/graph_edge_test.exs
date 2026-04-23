defmodule Ancestry.People.GraphEdgeTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.GraphEdge

  test "creates a parent_child edge" do
    edge = %GraphEdge{
      type: :parent_child,
      relationship_kind: "parent",
      from_id: "node-1",
      to_id: "node-2"
    }

    assert edge.type == :parent_child
    assert edge.relationship_kind == "parent"
    assert edge.from_id == "node-1"
    assert edge.to_id == "node-2"
  end

  test "creates a current_partner edge" do
    edge = %GraphEdge{
      type: :current_partner,
      relationship_kind: "married",
      from_id: "node-3",
      to_id: "node-4"
    }

    assert edge.type == :current_partner
    assert edge.relationship_kind == "married"
    assert edge.from_id == "node-3"
    assert edge.to_id == "node-4"
  end

  test "JSON encodes correctly — type atoms become strings, all fields present" do
    edge = %GraphEdge{
      type: :parent_child,
      relationship_kind: "parent",
      from_id: "node-1",
      to_id: "node-2"
    }

    encoded = Jason.encode!(edge)
    decoded = Jason.decode!(encoded)

    assert decoded["type"] == "parent_child"
    assert decoded["relationship_kind"] == "parent"
    assert decoded["from_id"] == "node-1"
    assert decoded["to_id"] == "node-2"
    assert Map.has_key?(decoded, "type")
    assert Map.has_key?(decoded, "relationship_kind")
    assert Map.has_key?(decoded, "from_id")
    assert Map.has_key?(decoded, "to_id")
  end
end
