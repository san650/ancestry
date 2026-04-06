defmodule Web.FamilyLive.PersonCardComponent do
  use Web, :html

  alias Ancestry.People.Person

  # --- Person Card ---

  attr :person, Person, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true
  attr :focused, :boolean, default: false
  attr :has_more, :boolean, default: false

  def person_card(assigns) do
    ~H"""
    <button
      type="button"
      data-person-id={@person.id}
      id={if(@focused, do: "focus-person-card", else: "person-card-#{@person.id}")}
      phx-click="focus_person"
      phx-value-id={@person.id}
      class={[
        "relative flex flex-col items-center text-center rounded-ds-sharp transition-all duration-150 group",
        "bg-ds-surface-card",
        gender_border_class(@person.gender),
        if(@focused, do: "ring-2 ring-ds-primary scale-105 z-1", else: "hover:bg-ds-surface-high"),
        "focus-visible:outline-2 focus-visible:outline-ds-primary focus-visible:outline-offset-2",
        "w-[72px] lg:w-28 lg:p-2"
      ]}
      aria-label={"#{Person.display_name(@person)}"}
    >
      <%!-- Mobile: photo fills card with name overlay --%>
      <div class="relative w-full h-[72px] lg:hidden overflow-hidden rounded-b-ds-sharp">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-[72px] object-cover"
          />
        <% else %>
          <div class={["w-full h-[72px] flex items-center justify-center", "bg-ds-surface-low"]}>
            <.icon name="hero-user" class={["w-7 h-7", gender_icon_class(@person.gender)]} />
          </div>
        <% end %>
        <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent px-1 py-0.5">
          <p class="text-[9px] font-semibold text-white leading-tight line-clamp-2">
            {Person.display_name(@person)}
          </p>
        </div>
      </div>
      <%!-- Desktop: circular photo, name below, dates below name --%>
      <div class="hidden lg:flex lg:flex-col lg:items-center">
        <div class="w-14 h-14 rounded-full bg-ds-primary/10 flex items-center justify-center overflow-hidden mb-1 group-hover:ring-2 group-hover:ring-ds-primary/50 transition-all">
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
        <p class="text-xs font-medium text-ds-on-surface w-full group-hover:text-ds-primary transition-colors line-clamp-2 leading-tight min-h-[2lh]">
          {Person.display_name(@person)}
        </p>
        <p class="text-[10px] text-ds-on-surface-variant">
          <%= if @person.birth_year do %>
            {format_life_span(@person)}
          <% else %>
            &nbsp;
          <% end %>
        </p>
        <%= if @has_more do %>
          <div class="mt-1 text-ds-on-surface-variant/50" title="Has more descendants">
            <.icon name="hero-chevron-down" class="w-3 h-3" />
          </div>
        <% end %>
      </div>
    </button>
    """
  end

  # --- Placeholder Card ---

  attr :type, :atom, required: true, values: [:parent, :partner, :child]
  attr :person_id, :integer, default: nil

  def placeholder_card(assigns) do
    ~H"""
    <button
      phx-click="add_relationship"
      phx-value-type={@type}
      phx-value-person-id={@person_id}
      class="flex flex-col items-center justify-center text-center w-[72px] h-[72px] lg:w-28 lg:h-auto lg:p-2 rounded-ds-sharp border border-dashed border-ds-on-surface-variant/50 hover:border-ds-primary/50 hover:bg-ds-primary/5 transition-all cursor-pointer group"
    >
      <div class="w-8 h-8 lg:w-14 lg:h-14 rounded-full bg-ds-on-surface/5 flex items-center justify-center mb-1 group-hover:bg-ds-primary/10 transition-colors">
        <.icon
          name="hero-plus"
          class="w-4 h-4 lg:w-6 lg:h-6 text-ds-on-surface-variant/50 group-hover:text-ds-primary transition-colors"
        />
      </div>
      <p class="text-[9px] lg:text-xs text-ds-on-surface-variant group-hover:text-ds-primary transition-colors">
        {placeholder_label(@type)}
      </p>
    </button>
    """
  end

  # --- Couple Card ---

  attr :person_a, :map, default: nil
  attr :person_b, :map, default: nil
  attr :ex_partners, :list, default: []
  attr :previous_partners, :list, default: []
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true
  attr :focused_person_id, :integer, default: nil
  attr :show_partner_placeholder, :boolean, default: false
  attr :person_for_placeholder, :integer, default: nil

  def couple_card(assigns) do
    ~H"""
    <div
      data-couple-card
      data-person-a-id={@person_a && @person_a.id}
      data-person-b-id={@person_b && @person_b.id}
      class="inline-flex items-stretch gap-0 rounded-ds-sharp bg-ds-surface-low/30 p-1"
    >
      <%!-- Ex-partners on the sides --%>
      <%= for ex_group <- @ex_partners do %>
        <.person_card
          person={ex_group.person}
          family_id={@family_id}
          organization={@organization}
          focused={false}
        />
        <div data-ex-separator={ex_group.person.id} class="w-[40px] self-stretch"></div>
      <% end %>
      <%!-- Previous partners on the sides --%>
      <%= for prev_group <- @previous_partners do %>
        <.person_card
          person={prev_group.person}
          family_id={@family_id}
          organization={@organization}
          focused={false}
        />
        <div data-previous-separator={prev_group.person.id} class="w-[40px] self-stretch"></div>
      <% end %>
      <%= cond do %>
        <% @person_a && @person_b -> %>
          <.person_card
            person={@person_a}
            family_id={@family_id}
            organization={@organization}
            focused={@person_a.id == @focused_person_id}
          />
          <.person_card
            person={@person_b}
            family_id={@family_id}
            organization={@organization}
            focused={@person_b.id == @focused_person_id}
          />
        <% @person_a && @show_partner_placeholder -> %>
          <.person_card
            person={@person_a}
            family_id={@family_id}
            organization={@organization}
            focused={@person_a.id == @focused_person_id}
          />
          <.placeholder_card
            type={:partner}
            person_id={@person_for_placeholder}
          />
        <% @person_a -> %>
          <.person_card
            person={@person_a}
            family_id={@family_id}
            organization={@organization}
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
  attr :organization, :map, required: true
  attr :focused_person_id, :integer, default: nil
  attr :is_root, :boolean, default: false

  def family_subtree(assigns) do
    previous_partners = Map.get(assigns.unit, :previous_partners, [])

    all_children =
      Enum.flat_map(assigns.unit.ex_partners, fn ex_group ->
        Enum.map(ex_group.children, &Map.put(&1, :line_origin, "ex-#{ex_group.person.id}"))
      end) ++
        Enum.flat_map(previous_partners, fn prev_group ->
          Enum.map(
            prev_group.children,
            &Map.put(&1, :line_origin, "prev-#{prev_group.person.id}")
          )
        end) ++
        Enum.map(assigns.unit.solo_children, &Map.put(&1, :line_origin, "solo")) ++
        Enum.map(assigns.unit.partner_children, &Map.put(&1, :line_origin, "partner"))

    has_children =
      all_children != [] or assigns.unit.ex_partners != [] or previous_partners != []

    assigns =
      assign(assigns,
        all_children: all_children,
        has_children: has_children,
        previous_partners: previous_partners
      )

    ~H"""
    <div class="flex items-start justify-center gap-4 lg:gap-8">
      <%!-- Main person + partner --%>
      <div
        class={["flex flex-col items-center", @is_root && "scroll-mt-4"]}
        data-primary-column
      >
        <.couple_card
          person_a={@unit.focus}
          person_b={@unit.partner}
          ex_partners={@unit.ex_partners}
          previous_partners={@previous_partners}
          family_id={@family_id}
          organization={@organization}
          focused_person_id={@focused_person_id}
          show_partner_placeholder={@is_root && is_nil(@unit.partner)}
          person_for_placeholder={@unit.focus.id}
        />
        <%= if @all_children != [] do %>
          <.subtree_children
            children={@all_children}
            family_id={@family_id}
            organization={@organization}
            focused_person_id={@focused_person_id}
          />
        <% end %>
        <%!-- Add child placeholder --%>
        <%= if @is_root and not @has_children do %>
          <.vline />
          <.placeholder_card type={:child} person_id={@unit.focus.id} />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Subtree Children ---

  attr :children, :list, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true
  attr :focused_person_id, :integer, default: nil

  def subtree_children(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <div class="flex items-start gap-3 lg:gap-6" data-children-row>
        <%= for child <- @children do %>
          <div
            class="flex flex-col items-center"
            data-child-column
            data-child-person-id={child_person_id(child)}
            data-line-origin={child[:line_origin]}
          >
            <%= cond do %>
              <% Map.get(child, :has_more, false) -> %>
                <.couple_card
                  person_a={child.person}
                  person_b={child[:partner]}
                  family_id={@family_id}
                  organization={@organization}
                  focused_person_id={@focused_person_id}
                />
                <div
                  class="flex flex-col items-center mt-1 text-ds-on-surface-variant/50"
                  title="Has more descendants"
                >
                  <.vline height={8} />
                  <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
                </div>
              <% Map.has_key?(child, :partner_children) -> %>
                <.family_subtree
                  unit={child}
                  family_id={@family_id}
                  organization={@organization}
                  focused_person_id={@focused_person_id}
                />
              <% true -> %>
                <.couple_card
                  person_a={child.person}
                  person_b={child[:partner]}
                  family_id={@family_id}
                  organization={@organization}
                  focused_person_id={@focused_person_id}
                />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Ancestor Subtree (recursive, renders parents above) ---

  attr :node, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true
  attr :focused_person_id, :integer, default: nil

  def ancestor_subtree(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <%= if @node.parent_trees != [] do %>
        <div
          class="flex items-end justify-center gap-4 lg:gap-8 mb-3 lg:mb-5"
          data-ancestor-parents-row
        >
          <%= for entry <- @node.parent_trees do %>
            <div data-ancestor-parent-column data-target-person-id={entry.for_person_id}>
              <.ancestor_subtree
                node={entry.tree}
                family_id={@family_id}
                organization={@organization}
                focused_person_id={@focused_person_id}
              />
            </div>
          <% end %>
        </div>
      <% end %>
      <.couple_card
        person_a={@node.couple.person_a}
        person_b={@node.couple.person_b}
        family_id={@family_id}
        organization={@organization}
        focused_person_id={@focused_person_id}
      />
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
        class="text-ds-on-surface-variant/50"
        stroke-width="3"
      />
    </svg>
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

  defp placeholder_label(:parent), do: "Add Parent"
  defp placeholder_label(:partner), do: "Add Partner"
  defp placeholder_label(:child), do: "Add Child"

  defp child_person_id(%{person: person}), do: person.id
  defp child_person_id(%{focus: person}), do: person.id
end
