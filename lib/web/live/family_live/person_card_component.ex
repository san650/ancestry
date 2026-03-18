defmodule Web.FamilyLive.PersonCardComponent do
  use Web, :html

  alias Ancestry.People.Person

  # --- Person Card ---

  attr :person, Person, required: true
  attr :family_id, :integer, required: true
  attr :focused, :boolean, default: false
  attr :has_more, :boolean, default: false

  def person_card(assigns) do
    ~H"""
    <div class={[
      "relative flex flex-col items-center text-center w-28 rounded-lg p-2 transition-all",
      "border border-base-content/10",
      gender_border_class(@person.gender),
      @focused && "ring-2 ring-primary",
      @person.deceased && "opacity-75"
    ]}>
      <.link
        navigate={~p"/families/#{@family_id}/members/#{@person.id}"}
        class="absolute top-1 right-1 p-0.5 rounded text-base-content/30 hover:text-primary hover:bg-primary/10 transition-colors z-10"
        title="View details"
      >
        <.icon name="hero-arrow-top-right-on-square-mini" class="w-3 h-3" />
      </.link>

      <button
        phx-click="focus_person"
        phx-value-id={@person.id}
        class="flex flex-col items-center cursor-pointer group"
      >
        <div class="w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden mb-1 group-hover:ring-2 group-hover:ring-primary/50 transition-all">
          <%= if @person.photo && @person.photo_status == "processed" do %>
            <img
              src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
              alt={Person.display_name(@person)}
              class="w-full h-full object-cover"
            />
          <% else %>
            <.icon name="hero-user" class={["w-7 h-7", gender_icon_class(@person.gender)]} />
          <% end %>
        </div>
        <p class="text-xs font-medium text-base-content w-full group-hover:text-primary transition-colors line-clamp-2 leading-tight min-h-[2lh]">
          {Person.display_name(@person)}
        </p>
        <p class="text-[10px] text-base-content/50">
          <%= if @person.birth_year do %>
            {format_life_span(@person)}
          <% else %>
            &nbsp;
          <% end %>
        </p>
      </button>
      <%= if @has_more do %>
        <div class="mt-1 text-base-content/30" title="Has more descendants">
          <.icon name="hero-chevron-down" class="w-3 h-3" />
        </div>
      <% end %>
    </div>
    """
  end

  # --- Placeholder Card ---

  attr :type, :atom, required: true, values: [:parent, :spouse, :child]
  attr :person_id, :integer, default: nil
  attr :family_id, :integer, required: true

  def placeholder_card(assigns) do
    ~H"""
    <.link
      navigate={placeholder_link(@type, @person_id, @family_id)}
      class="flex flex-col items-center text-center w-28 rounded-lg p-2 border border-dashed border-base-content/20 hover:border-primary/50 hover:bg-primary/5 transition-all cursor-pointer group"
    >
      <div class="w-14 h-14 rounded-full bg-base-content/5 flex items-center justify-center mb-1 group-hover:bg-primary/10 transition-colors">
        <.icon
          name="hero-plus"
          class="w-6 h-6 text-base-content/30 group-hover:text-primary transition-colors"
        />
      </div>
      <p class="text-xs text-base-content/40 group-hover:text-primary transition-colors">
        {placeholder_label(@type)}
      </p>
    </.link>
    """
  end

  # --- Couple Card ---

  attr :person_a, :map, default: nil
  attr :person_b, :map, default: nil
  attr :family_id, :integer, required: true
  attr :focused_person_id, :integer, default: nil
  attr :show_spouse_placeholder, :boolean, default: false
  attr :person_for_placeholder, :integer, default: nil

  def couple_card(assigns) do
    ~H"""
    <div class="inline-flex items-stretch gap-0 rounded-lg bg-base-200/30 p-1">
      <%= cond do %>
        <% @person_a && @person_b -> %>
          <.person_card
            person={@person_a}
            family_id={@family_id}
            focused={@person_a.id == @focused_person_id}
          />
          <.person_card
            person={@person_b}
            family_id={@family_id}
            focused={@person_b.id == @focused_person_id}
          />
        <% @person_a && @show_spouse_placeholder -> %>
          <.person_card
            person={@person_a}
            family_id={@family_id}
            focused={@person_a.id == @focused_person_id}
          />
          <.placeholder_card
            type={:spouse}
            person_id={@person_for_placeholder}
            family_id={@family_id}
          />
        <% @person_a -> %>
          <.person_card
            person={@person_a}
            family_id={@family_id}
            focused={@person_a.id == @focused_person_id}
          />
        <% true -> %>
          <div class="w-28"></div>
      <% end %>
    </div>
    """
  end

  # --- Family Subtree (recursive) ---

  attr :unit, :map, required: true
  attr :family_id, :integer, required: true
  attr :focused_person_id, :integer, default: nil
  attr :is_root, :boolean, default: false

  def family_subtree(assigns) do
    all_children = assigns.unit.partner_children ++ assigns.unit.solo_children
    has_children = all_children != [] or assigns.unit.ex_partners != []

    assigns =
      assign(assigns,
        all_children: all_children,
        has_children: has_children
      )

    ~H"""
    <div class="flex items-start justify-center gap-8">
      <%!-- Ex-partners on the sides --%>
      <%= for ex_group <- @unit.ex_partners do %>
        <div class="flex flex-col items-center">
          <.couple_card
            person_a={ex_group.person}
            family_id={@family_id}
            focused_person_id={@focused_person_id}
          />
          <%= if ex_group.children != [] do %>
            <.vline />
            <.subtree_children
              children={ex_group.children}
              family_id={@family_id}
              focused_person_id={@focused_person_id}
            />
          <% end %>
        </div>
      <% end %>

      <%!-- Main person + partner --%>
      <div
        class={["flex flex-col items-center", @is_root && "scroll-mt-4"]}
        id={if(@is_root, do: "focus-person-card")}
      >
        <.couple_card
          person_a={@unit.focus}
          person_b={@unit.partner}
          family_id={@family_id}
          focused_person_id={@focused_person_id}
          show_spouse_placeholder={@is_root && is_nil(@unit.partner)}
          person_for_placeholder={@unit.focus.id}
        />
        <%= if @all_children != [] do %>
          <.vline />
          <.subtree_children
            children={@all_children}
            family_id={@family_id}
            focused_person_id={@focused_person_id}
          />
        <% end %>
        <%!-- Add child placeholder --%>
        <%= if @is_root and not @has_children do %>
          <.vline />
          <.placeholder_card type={:child} person_id={@unit.focus.id} family_id={@family_id} />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Subtree Children ---

  attr :children, :list, required: true
  attr :family_id, :integer, required: true
  attr :focused_person_id, :integer, default: nil

  def subtree_children(assigns) do
    assigns = assign(assigns, :connector_id, "conn-#{System.unique_integer([:positive])}")

    ~H"""
    <div class="flex flex-col items-center">
      <%!-- SVG connector drawn by JS hook --%>
      <div
        id={@connector_id}
        phx-hook=".BranchConnector"
        phx-update="ignore"
        class="w-full"
        style="height: 20px; position: relative;"
      >
        <svg class="absolute inset-0 w-full h-full overflow-visible"></svg>
      </div>
      <div class="flex items-start gap-6" data-children-row>
        <%= for child <- @children do %>
          <div class="flex flex-col items-center" data-child-column>
            <%= cond do %>
              <% Map.get(child, :has_more, false) -> %>
                <.couple_card
                  person_a={child.person}
                  person_b={child[:partner]}
                  family_id={@family_id}
                  focused_person_id={@focused_person_id}
                />
                <div
                  class="flex flex-col items-center mt-1 text-base-content/30"
                  title="Has more descendants"
                >
                  <.vline height={8} />
                  <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
                </div>
              <% Map.has_key?(child, :partner_children) -> %>
                <.family_subtree
                  unit={child}
                  family_id={@family_id}
                  focused_person_id={@focused_person_id}
                />
              <% true -> %>
                <.couple_card
                  person_a={child.person}
                  person_b={child[:partner]}
                  family_id={@family_id}
                  focused_person_id={@focused_person_id}
                />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- SVG Connectors ---

  attr :height, :integer, default: 16

  def vline(assigns) do
    ~H"""
    <svg width="2" height={@height} class="block mx-auto" viewBox={"0 0 2 #{@height}"}>
      <line
        x1="1"
        y1="0"
        x2="1"
        y2={@height}
        stroke="currentColor"
        class="text-base-content/20"
        stroke-width="1"
      />
    </svg>
    """
  end

  # --- Private helpers ---

  defp gender_border_class("male"), do: "border-t-2 border-t-blue-400"
  defp gender_border_class("female"), do: "border-t-2 border-t-pink-400"
  defp gender_border_class(_), do: "border-t-2 border-t-base-content/20"

  defp gender_icon_class("male"), do: "text-blue-400"
  defp gender_icon_class("female"), do: "text-pink-400"
  defp gender_icon_class(_), do: "text-primary"

  defp format_life_span(person) do
    birth = person.birth_year
    death = if person.deceased, do: person.death_year || "?", else: nil

    case {birth, death} do
      {nil, _} -> ""
      {b, nil} -> "#{b}"
      {b, d} -> "#{b}\u2013#{d}"
    end
  end

  defp placeholder_label(:parent), do: "Add Parent"
  defp placeholder_label(:spouse), do: "Add Spouse"
  defp placeholder_label(:child), do: "Add Child"

  defp placeholder_link(_type, person_id, family_id) when is_integer(person_id) do
    ~p"/families/#{family_id}/members/#{person_id}"
  end

  defp placeholder_link(_type, _person_id, family_id) do
    ~p"/families/#{family_id}/members/new"
  end
end
