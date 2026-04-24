defmodule Web.FamilyLive.PrintGraphComponent do
  use Web, :html

  alias Ancestry.People.Person
  alias Ancestry.People.PersonGraph

  # --- Print Graph Canvas ---

  attr :graph, PersonGraph, required: true

  def print_graph_canvas(assigns) do
    ~H"""
    <div
      id="graph-canvas"
      phx-hook="GraphConnector"
      data-edges={Jason.encode!(@graph.edges)}
      class="relative overflow-visible"
    >
      <div
        data-graph-grid
        style={"display:grid; grid-template-columns:repeat(#{@graph.grid_cols}, 120px); grid-template-rows:repeat(#{@graph.grid_rows}, auto); gap:48px 12px;"}
        class="w-fit mx-auto"
      >
        <%= for node <- @graph.nodes do %>
          <.print_cell node={node} />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Print Cell ---

  defp print_cell(%{node: %{type: :separator}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1}"}
      aria-hidden="true"
    />
    """
  end

  defp print_cell(%{node: %{type: :person}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      data-node-id={@node.id}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1}"}
      class="relative z-10 flex items-center justify-center"
    >
      <.print_person_card person={@node.person} />
    </div>
    """
  end

  # --- Print Person Card ---

  defp print_person_card(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-center text-center w-[120px] h-[40px] px-1 py-2",
      "bg-white border border-gray-300 rounded-sm",
      gender_border_class(@person.gender)
    ]}>
      <p class="text-xs font-medium text-black leading-tight line-clamp-2">
        {Person.display_name(@person)}
      </p>
    </div>
    """
  end

  defp gender_border_class("male"), do: "border-t-2 border-t-blue-400"
  defp gender_border_class("female"), do: "border-t-2 border-t-pink-400"
  defp gender_border_class(_), do: "border-t-2 border-t-gray-400"
end
