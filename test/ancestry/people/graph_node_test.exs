defmodule Ancestry.People.GraphNodeTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.GraphNode

  test "creates a person node with all fields" do
    person = %{id: 1, name: "Alice"}

    node = %GraphNode{
      id: "node-1",
      type: :person,
      col: 2,
      row: 3,
      person: person,
      focus: true,
      duplicated: true,
      has_more_up: true,
      has_more_down: true
    }

    assert node.id == "node-1"
    assert node.type == :person
    assert node.col == 2
    assert node.row == 3
    assert node.person == person
    assert node.focus == true
    assert node.duplicated == true
    assert node.has_more_up == true
    assert node.has_more_down == true
  end

  test "creates a separator node (person is nil)" do
    node = %GraphNode{
      id: "sep-0-1",
      type: :separator,
      col: 0,
      row: 1
    }

    assert node.type == :separator
    assert node.person == nil
    assert node.id == "sep-0-1"
  end

  test "defaults boolean fields to false" do
    node = %GraphNode{id: "node-2", type: :person, col: 0, row: 0}

    assert node.focus == false
    assert node.duplicated == false
    assert node.has_more_up == false
    assert node.has_more_down == false
  end
end
