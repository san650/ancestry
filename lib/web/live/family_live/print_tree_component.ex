defmodule Web.FamilyLive.PrintTreeComponent do
  use Web, :html

  alias Ancestry.People.Person

  @doc "Renders the full print tree as an indented list."
  attr :tree, :map, required: true

  def print_tree(assigns) do
    ~H"""
    <div class="font-['Inter',system-ui,sans-serif] text-[11.5px] text-[#1a1a1a] leading-[1.9]">
      <%= for root <- @tree.roots do %>
        <.tree_entry entry={root} focus_person_id={@tree.focus_person_id} />
      <% end %>
    </div>
    """
  end

  # --- Entry dispatcher ---

  defp tree_entry(%{entry: %{duplicated: true}} = assigns) do
    ~H"""
    <div class="text-gray-400 italic text-[10px]">
      &rarr; {Person.display_name(@entry.person)} ({gettext("see above")})
    </div>
    """
  end

  defp tree_entry(%{entry: %{type: :person}} = assigns) do
    ~H"""
    <div>
      <%!-- Person line --%>
      <div class={
        if @entry.is_focus,
          do: "bg-blue-50 -mx-2 px-2 py-0.5 rounded border-l-[3px] border-l-blue-500",
          else: ""
      }>
        <.gender_icon gender={@entry.person.gender} />
        <span class={if @entry.is_focus, do: "font-bold text-blue-700", else: "font-semibold"}>
          {Person.display_name(@entry.person)}
        </span>
        <.life_span person={@entry.person} />
      </div>

      <%!-- Partners and their children --%>
      <%= if @entry.partners != [] or @entry.solo_children != [] do %>
        <div class="ml-6 border-l-[1.5px] border-gray-200 pl-3">
          <%= for partner_entry <- @entry.partners do %>
            <.partner_block entry={partner_entry} focus_person_id={@focus_person_id} />
          <% end %>

          <%!-- Solo children --%>
          <%= if @entry.solo_children != [] do %>
            <div class="text-gray-400 italic text-[10px] mt-1">
              {gettext("no known partner")}:
            </div>
            <%= for child <- @entry.solo_children do %>
              <.tree_entry entry={child} focus_person_id={@focus_person_id} />
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Partner block ---

  defp partner_block(assigns) do
    ~H"""
    <div>
      <%!-- Partner line with relationship type --%>
      <div class="text-gray-400 text-[10px]">
        <.gender_icon gender={@entry.person.gender} />
        <em>{relationship_label(@entry.relationship_type)}</em>
        <strong class="text-gray-600">{Person.display_name(@entry.person)}</strong>
        <.life_span person={@entry.person} />
      </div>

      <%!-- Children of this partnership --%>
      <%= if @entry.children != [] do %>
        <div class="ml-6 border-l-[1.5px] border-gray-200 pl-3">
          <%= for child <- @entry.children do %>
            <.tree_entry entry={child} focus_person_id={@focus_person_id} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp gender_icon(assigns) do
    ~H"""
    <span class={["text-[7px]", gender_color(@gender)]}>&#9632;</span>
    """
  end

  defp life_span(assigns) do
    ~H"""
    <span class="text-gray-400 text-[10px]">
      <%= cond do %>
        <% @person.birth_year && @person.deceased -> %>
          ({@person.birth_year}&ndash;{@person.death_year || "?"})
        <% @person.birth_year -> %>
          ({@person.birth_year})
        <% true -> %>
      <% end %>
    </span>
    """
  end

  defp gender_color("male"), do: "text-blue-400"
  defp gender_color("female"), do: "text-pink-400"
  defp gender_color(_), do: "text-gray-400"

  defp relationship_label("married"), do: gettext("married to")
  defp relationship_label("relationship"), do: gettext("partner of")
  defp relationship_label("divorced"), do: gettext("divorced from")
  defp relationship_label("separated"), do: gettext("separated from")
  defp relationship_label(_), do: gettext("partner of")
end
