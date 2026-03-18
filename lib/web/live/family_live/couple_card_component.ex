defmodule Web.FamilyLive.CoupleCardComponent do
  use Web, :html

  import Web.FamilyLive.PersonCardComponent

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
end
