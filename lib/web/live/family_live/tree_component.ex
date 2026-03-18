defmodule Web.FamilyLive.TreeComponent do
  use Web, :live_component

  alias Web.FamilyLive.PersonCardComponent
  alias Web.FamilyLive.UnionConnectorComponent
  alias Web.FamilyLive.ConnectorCellComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="family-tree-grid"
      style={"grid-template-columns: repeat(#{@grid.cols}, minmax(8rem, 1fr)); grid-template-rows: repeat(#{@grid.rows}, auto);"}
    >
      <%= for {{row, col}, cell} <- @grid.cells do %>
        <%= case cell.type do %>
          <% :person -> %>
            <div
              style={"grid-row: #{row + 1}; grid-column: #{col + 1};"}
              class="flex items-center justify-center p-2"
            >
              <.link navigate={~p"/families/#{@family_id}/members/#{cell.data.person_id}"}>
                <.live_component
                  module={PersonCardComponent}
                  id={"person-card-#{cell.data.person_id}"}
                  person={@graph.nodes[cell.data.person_id].person}
                />
              </.link>
            </div>
          <% :union -> %>
            <div
              style={"grid-row: #{row + 1}; grid-column: #{col + 1};"}
              class="flex items-center justify-center"
            >
              <.live_component
                module={UnionConnectorComponent}
                id={"union-#{cell.data.union_id}"}
                type={lookup_union_type(@graph.unions, cell.data.union_id)}
              />
            </div>
          <% connector_type -> %>
            <div style={"grid-row: #{row + 1}; grid-column: #{col + 1};"}>
              <.live_component
                module={ConnectorCellComponent}
                id={"connector-#{row}-#{col}"}
                type={connector_type}
              />
            </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp lookup_union_type(unions, union_id) do
    case Enum.find(unions, fn u -> u.id == union_id end) do
      nil -> :partner
      union -> union.type
    end
  end
end
