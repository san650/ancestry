defmodule Web.PersonLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)
    people = People.list_people_for_family(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> stream(:people, people)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}
end
