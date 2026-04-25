defmodule Web.FamilyLive.TreeComponent do
  use Web, :html

  alias Ancestry.People.Person

  # --- Tree Canvas ---

  @doc "Renders the interactive tree view from a PersonTree nested structure."
  attr :tree, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  def tree_canvas(assigns) do
    ~H"""
    <div id="tree-canvas-inner" class="flex flex-col gap-2 p-4" {test_id("tree-canvas")}>
      <.tree_entry
        :for={root <- @tree.roots}
        entry={root}
        family_id={@family_id}
        organization={@organization}
      />
    </div>
    """
  end

  # --- Entry dispatcher ---

  attr :entry, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp tree_entry(%{entry: %{duplicated: true}} = assigns) do
    ~H"""
    <button
      type="button"
      phx-click={scroll_to_person(@entry.person.id)}
      class="flex items-center gap-2 px-3 py-1.5 italic text-xs text-ds-on-surface-variant/60 hover:text-ds-primary transition-colors cursor-pointer"
    >
      <.icon name="hero-arrow-turn-right-up" class="w-3.5 h-3.5" />
      <span>{Person.display_name(@entry.person)}</span>
      <span class="text-[10px]">({gettext("see above")})</span>
    </button>
    """
  end

  defp tree_entry(%{entry: %{type: :person}} = assigns) do
    ~H"""
    <div>
      <.person_row entry={@entry} family_id={@family_id} organization={@organization} />

      <%!-- Partners and children, indented with connector line --%>
      <div
        :if={@entry.partners != [] or @entry.solo_children != []}
        class="pl-6 border-l-2 border-dotted border-ds-on-surface/30 flex flex-col gap-1 mt-1 pb-3"
      >
        <.partner_block
          :for={partner <- @entry.partners}
          entry={partner}
          family_id={@family_id}
          organization={@organization}
        />

        <%!-- Solo children --%>
        <div :if={@entry.solo_children != []} class="flex flex-col gap-1">
          <span class="text-[10px] text-ds-on-surface-variant/50 italic">
            {gettext("no known partner")}:
          </span>
          <.tree_entry
            :for={child <- @entry.solo_children}
            entry={child}
            family_id={@family_id}
            organization={@organization}
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Partner block ---

  attr :entry, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp partner_block(assigns) do
    ~H"""
    <div>
      <%!-- Partner rendered as a person card with relationship label inside --%>
      <button
        type="button"
        phx-click="focus_person"
        phx-value-id={@entry.person.id}
        class={[
          "flex flex-col shadow-ds-ambient transition-all duration-150 text-left group",
          "bg-ds-surface-card border-l-2 hover:bg-ds-surface-high",
          gender_border_class(@entry.person.gender),
          "focus-visible:outline-2 focus-visible:outline-ds-primary focus-visible:outline-offset-2"
        ]}
        aria-label={Person.display_name(@entry.person)}
      >
        <%!-- Relationship label row --%>
        <span class="flex items-center gap-1 text-[11px] font-ds-body text-ds-on-surface-variant/70 px-3 pt-1.5">
          <.icon name="hero-arrow-turn-down-right" class="w-3 h-3" />
          {relationship_label(@entry.relationship_type)}
        </span>
        <%!-- Person info row --%>
        <div class="flex items-center gap-2.5 px-3 pb-2 pt-1">
          <%!-- Has more ancestors indicator --%>
          <div
            :if={@entry.has_more_up}
            class="flex items-center justify-center w-5 h-5 rounded-full bg-ds-surface-low text-ds-on-surface-variant/60"
            title={gettext("Has more ascendants not shown")}
          >
            <.icon name="hero-share" class="w-3 h-3" />
          </div>
          <%!-- Photo circle (32px) --%>
          <div class="w-8 h-8 rounded-full flex-shrink-0 flex items-center justify-center overflow-hidden bg-ds-surface-low">
            <%= if @entry.person.photo && @entry.person.photo_status == "processed" do %>
              <img
                src={
                  Ancestry.Uploaders.PersonPhoto.url(
                    {@entry.person.photo, @entry.person},
                    :thumbnail
                  )
                }
                alt={Person.display_name(@entry.person)}
                class="w-full h-full object-cover"
              />
            <% else %>
              <.icon
                name="hero-user"
                class={["w-4 h-4", gender_icon_class(@entry.person.gender)]}
              />
            <% end %>
          </div>
          <%!-- Name --%>
          <span class="text-sm font-ds-body font-medium whitespace-nowrap text-ds-on-surface group-hover:text-ds-primary">
            {Person.display_name(@entry.person)}
          </span>
          <%!-- Dates --%>
          <span class="text-xs font-ds-body flex-shrink-0 text-ds-on-surface-variant">
            {format_life_span(@entry.person)}
          </span>
          <%!-- Navigate-to-person link (desktop only) --%>
          <.link
            navigate={~p"/org/#{@organization.id}/people/#{@entry.person.id}"}
            class="hidden lg:flex items-center justify-center w-5 h-5 rounded-full bg-ds-surface-low/80 hover:bg-ds-primary hover:text-white transition-colors opacity-0 group-hover:opacity-100"
            aria-label={gettext("View person")}
          >
            <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" />
          </.link>
        </div>
      </button>

      <%!-- Children of this partnership --%>
      <div
        :if={@entry.children != []}
        class="pl-6 border-ds-on-surface/30 flex flex-col gap-1 mt-1 pb-3"
      >
        <span class="flex items-center gap-1 text-[11px] font-ds-body text-ds-on-surface-variant/70 bg-ds-background px-1">
          <.icon name="hero-user-group" class="w-3 h-3" />
          {ngettext("1 child", "%{count} children", length(@entry.children))}
        </span>
        <.tree_entry
          :for={child <- @entry.children}
          entry={child}
          family_id={@family_id}
          organization={@organization}
        />
      </div>
    </div>
    """
  end

  # --- Person Row (main person card) ---

  attr :entry, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp person_row(assigns) do
    ~H"""
    <button
      id={"tree-person-#{@entry.person.id}"}
      type="button"
      phx-click="focus_person"
      phx-value-id={@entry.person.id}
      class={[
        "flex items-center gap-2.5 px-3 py-2 shadow-ds-ambient transition-all duration-150 text-left group",
        if(@entry.is_focus,
          do: "bg-ds-primary-container text-ds-on-primary border-l-2 shadow-ds-ambient",
          else: "bg-ds-surface-card border-l-2 hover:bg-ds-surface-high"
        ),
        gender_border_class(@entry.person.gender),
        "focus-visible:outline-2 focus-visible:outline-ds-primary focus-visible:outline-offset-2"
      ]}
      aria-label={Person.display_name(@entry.person)}
    >
      <%!-- Has more ancestors indicator --%>
      <div
        :if={@entry.has_more_up}
        class={[
          "flex items-center justify-center w-5 h-5 rounded-full text-ds-on-surface-variant/60",
          if(@entry.is_focus, do: "bg-white/15", else: "bg-ds-surface-low")
        ]}
        title={gettext("Has more ascendants not shown")}
      >
        <.icon name="hero-share" class="w-3 h-3" />
      </div>

      <%!-- Photo circle (32px) --%>
      <div class={[
        "w-8 h-8 rounded-full flex-shrink-0 flex items-center justify-center overflow-hidden",
        if(@entry.is_focus, do: "bg-white/15", else: "bg-ds-surface-low")
      ]}>
        <%= if @entry.person.photo && @entry.person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@entry.person.photo, @entry.person}, :thumbnail)}
            alt={Person.display_name(@entry.person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon
            name="hero-user"
            class={["w-4 h-4", gender_icon_class(@entry.person.gender)]}
          />
        <% end %>
      </div>

      <%!-- Name --%>
      <span class={[
        "text-sm font-ds-body font-medium whitespace-nowrap",
        if(@entry.is_focus,
          do: "text-ds-on-primary",
          else: "text-ds-on-surface group-hover:text-ds-primary"
        )
      ]}>
        {Person.display_name(@entry.person)}
      </span>

      <%!-- Dates --%>
      <span class={[
        "text-xs font-ds-body flex-shrink-0",
        if(@entry.is_focus, do: "text-ds-on-primary/70", else: "text-ds-on-surface-variant")
      ]}>
        {format_life_span(@entry.person)}
      </span>

      <%!-- Navigate-to-person link (desktop only, appears on hover) --%>
      <.link
        navigate={~p"/org/#{@organization.id}/people/#{@entry.person.id}"}
        class={[
          "hidden lg:flex items-center justify-center w-5 h-5 rounded-full transition-colors",
          if(@entry.is_focus,
            do: "bg-white/15 hover:bg-white/30 opacity-100",
            else:
              "bg-ds-surface-low/80 hover:bg-ds-primary hover:text-white opacity-0 group-hover:opacity-100"
          )
        ]}
        aria-label={gettext("View person")}
      >
        <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" />
      </.link>

      <%!-- Has more descendants indicator --%>
      <div
        :if={@entry.has_more_down}
        class={[
          "flex items-center justify-center w-5 h-5 rounded-full text-ds-on-surface-variant/60",
          if(@entry.is_focus, do: "bg-white/15", else: "bg-ds-surface-low")
        ]}
        title={gettext("Has more descendants not shown")}
      >
        <.icon name="hero-share" class="w-3 h-3" />
      </div>
    </button>
    """
  end

  # --- JS commands ---

  defp scroll_to_person(person_id) do
    JS.dispatch("scroll-highlight", to: "#tree-person-#{person_id}")
  end

  # --- Private helpers ---

  defp gender_border_class("male"), do: "border-l-blue-400"
  defp gender_border_class("female"), do: "border-l-pink-400"
  defp gender_border_class(_), do: "border-l-ds-on-surface-variant/50"

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

  defp relationship_label("married"), do: gettext("married to")
  defp relationship_label("relationship"), do: gettext("partner of")
  defp relationship_label("divorced"), do: gettext("divorced from")
  defp relationship_label("separated"), do: gettext("separated from")
  defp relationship_label(_), do: gettext("partner of")
end
