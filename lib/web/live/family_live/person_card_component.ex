defmodule Web.FamilyLive.PersonCardComponent do
  use Web, :live_component

  alias Ancestry.People.Person

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col items-center text-center w-28">
      <div class="w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden mb-1">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-7 h-7 text-primary" />
        <% end %>
      </div>
      <p class="text-xs font-medium text-base-content truncate w-full">
        {Person.display_name(@person)}
      </p>
      <%= if @person.birth_year do %>
        <p class="text-[10px] text-base-content/50">
          {format_life_span(@person)}
        </p>
      <% end %>
    </div>
    """
  end

  defp format_life_span(person) do
    birth = person.birth_year
    death = if person.deceased, do: person.death_year || "?", else: nil

    case {birth, death} do
      {nil, _} -> ""
      {b, nil} -> "#{b}"
      {b, d} -> "#{b}--#{d}"
    end
  end
end
