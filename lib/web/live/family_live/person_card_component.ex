defmodule Web.FamilyLive.PersonCardComponent do
  use Web, :html

  alias Ancestry.People.Person

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

  attr :children, :list, required: true
  attr :family_id, :integer, required: true

  def children_row(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <%= if length(@children) > 1 do %>
        <div class="flex items-start">
          <%= for {child, idx} <- Enum.with_index(@children) do %>
            <div class="flex flex-col items-center">
              <div class={[
                "h-3 border-base-content/20",
                if(idx == 0, do: "border-r w-1/2 self-end", else: ""),
                if(idx == length(@children) - 1, do: "border-l w-1/2 self-start", else: ""),
                if(idx > 0 && idx < length(@children) - 1, do: "border-l border-r w-full", else: ""),
                "border-t"
              ]}>
              </div>
              <.person_card person={child} family_id={@family_id} focused={false} />
            </div>
            <%= if idx < length(@children) - 1 do %>
              <div class="h-3 border-t border-base-content/20 w-4 flex-shrink-0"></div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <%= for child <- @children do %>
          <.person_card person={child} family_id={@family_id} focused={false} />
        <% end %>
      <% end %>
    </div>
    """
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
