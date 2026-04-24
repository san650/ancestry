defmodule Web.FamilyLive.GraphComponent do
  use Web, :html

  alias Ancestry.People.Person
  alias Ancestry.People.PersonGraph

  # --- Graph Canvas ---

  attr :graph, PersonGraph, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  def graph_canvas(assigns) do
    ~H"""
    <div
      id="graph-canvas"
      phx-hook="GraphConnector"
      data-edges={Jason.encode!(@graph.edges)}
      class="relative overflow-auto hide-scrollbar p-6"
      {test_id("graph-canvas")}
    >
      <div
        data-graph-grid
        style={"display:grid; grid-template-columns:repeat(#{@graph.grid_cols}, 120px); grid-template-rows:repeat(#{@graph.grid_rows}, auto); gap:48px 12px;"}
        class="max-w-fit mx-auto"
      >
        <%= for node <- @graph.nodes do %>
          <.graph_cell
            node={node}
            family_id={@family_id}
            organization={@organization}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Graph Cell ---

  attr :node, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp graph_cell(%{node: %{type: :separator}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1}"}
      class="border border-dashed border-ds-outline-variant/10"
      aria-hidden="true"
    />
    """
  end

  defp graph_cell(%{node: %{type: :person}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      data-node-id={@node.id}
      data-focus={to_string(@node.focus)}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1}"}
      class="relative flex items-center justify-center border border-dashed border-ds-outline-variant/10"
    >
      <%!-- Has more ancestors — pill at top center, half outside card --%>
      <div
        :if={@node.has_more_up}
        class="absolute -top-3 left-1/2 -translate-x-1/2 z-10 flex items-center justify-center w-6 h-6 rounded-full bg-white border border-ds-outline-variant/30 text-ds-on-surface-variant/60 hover:bg-ds-surface-high hover:text-ds-on-surface-variant transition-colors cursor-pointer print:hidden"
        title={gettext("Has more ancestors")}
      >
        <.icon name="hero-chevron-up" class="w-3 h-3" />
      </div>
      <%!-- Has more descendants — pill at bottom center, half outside card --%>
      <div
        :if={@node.has_more_down}
        class="absolute -bottom-3 left-1/2 -translate-x-1/2 z-10 flex items-center justify-center w-6 h-6 rounded-full bg-white border border-ds-outline-variant/30 text-ds-on-surface-variant/60 hover:bg-ds-surface-high hover:text-ds-on-surface-variant transition-colors cursor-pointer print:hidden"
        title={gettext("Has more descendants")}
      >
        <.icon name="hero-chevron-down" class="w-3 h-3" />
      </div>
      <.person_card
        node={@node}
        family_id={@family_id}
        organization={@organization}
      />
    </div>
    """
  end

  # --- Person Card ---

  attr :node, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp person_card(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="focus_person"
      phx-value-id={@node.person.id}
      class={[
        "relative flex flex-col items-center text-center rounded-ds-sharp transition-all duration-150 group",
        if(@node.focus,
          do:
            "bg-ds-primary-container text-ds-on-primary border border-ds-primary-container shadow-ds-ambient z-1",
          else:
            "bg-ds-surface-card shadow-ds-ambient border border-ds-outline-variant/20 hover:bg-ds-surface-high"
        ),
        gender_border_class(@node.person.gender),
        "focus-visible:outline-2 focus-visible:outline-ds-primary focus-visible:outline-offset-2",
        "w-[72px] lg:w-28 lg:p-2",
        @node.duplicated && "opacity-50 border border-dashed border-ds-on-surface-variant/40"
      ]}
      aria-label={Person.display_name(@node.person)}
    >
      <%!-- Mobile: photo fills card with name overlay --%>
      <div class="relative w-full h-[72px] lg:hidden print:!hidden overflow-hidden rounded-b-ds-sharp">
        <%= if @node.person.photo && @node.person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@node.person.photo, @node.person}, :thumbnail)}
            alt={Person.display_name(@node.person)}
            class="w-full h-[72px] object-cover"
          />
        <% else %>
          <div class={["w-full h-[72px] flex items-center justify-center", "bg-ds-surface-low"]}>
            <.icon name="hero-user" class={["w-7 h-7", gender_icon_class(@node.person.gender)]} />
          </div>
        <% end %>
        <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent px-1 py-0.5">
          <p class="text-[9px] font-semibold text-white leading-tight line-clamp-2">
            {Person.display_name(@node.person)}
          </p>
        </div>
      </div>
      <%!-- Desktop: circular photo, name below, dates below name --%>
      <div class="hidden lg:flex print:!flex lg:flex-col lg:items-center lg:flex-1 lg:w-full">
        <div class="w-14 h-14 rounded-full bg-ds-primary/10 flex items-center justify-center overflow-hidden mb-1 group-hover:ring-2 group-hover:ring-ds-primary/50 transition-all print:hidden">
          <%= if @node.person.photo && @node.person.photo_status == "processed" do %>
            <img
              src={Ancestry.Uploaders.PersonPhoto.url({@node.person.photo, @node.person}, :thumbnail)}
              alt={Person.display_name(@node.person)}
              class="w-full h-full object-cover"
            />
          <% else %>
            <.icon
              name="hero-user"
              class={["w-7 h-7", gender_icon_class(@node.person.gender)]}
            />
          <% end %>
        </div>
        <p class={[
          "text-xs font-medium w-full transition-colors line-clamp-2 leading-tight min-h-[2lh]",
          if(@node.focus,
            do: "text-ds-on-primary",
            else: "text-ds-on-surface group-hover:text-ds-primary"
          )
        ]}>
          {Person.display_name(@node.person)}
        </p>
        <%= if @node.duplicated do %>
          <p class="text-[9px] text-ds-on-surface-variant/60 italic">
            {gettext("(duplicated)")}
          </p>
        <% end %>
        <p class={[
          "text-[10px]",
          if(@node.focus, do: "text-ds-on-primary/70", else: "text-ds-on-surface-variant")
        ]}>
          <%= if @node.person.birth_year do %>
            {format_life_span(@node.person)}
          <% else %>
            &nbsp;
          <% end %>
        </p>
      </div>
      <%!-- Navigation link to person page (overlaid, bottom-right) --%>
      <.link
        navigate={~p"/org/#{@organization.id}/people/#{@node.person.id}"}
        class="absolute bottom-1 right-1 hidden lg:flex print:!hidden items-center justify-center w-5 h-5 rounded-full bg-ds-surface-low/80 hover:bg-ds-primary hover:text-white transition-colors opacity-0 group-hover:opacity-100"
        aria-label={gettext("Go to person page")}
        title={gettext("View person")}
      >
        <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" />
      </.link>
    </button>
    """
  end

  # --- Private helpers ---

  defp gender_border_class("male"), do: "border-t-2 border-t-blue-400"
  defp gender_border_class("female"), do: "border-t-2 border-t-pink-400"
  defp gender_border_class(_), do: "border-t-2 border-t-ds-on-surface-variant/50"

  defp gender_icon_class("male"), do: "text-blue-400"
  defp gender_icon_class("female"), do: "text-pink-400"
  defp gender_icon_class(_), do: "text-ds-primary"

  defp format_life_span(person) do
    birth = person.birth_year
    death = if person.deceased, do: person.death_year || "?", else: nil

    case {birth, death} do
      {nil, _} -> ""
      {b, nil} -> "#{b}"
      {b, d} -> "#{b}\u2013#{d}"
    end
  end
end
