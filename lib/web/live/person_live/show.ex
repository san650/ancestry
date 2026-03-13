defmodule Web.PersonLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id, "id" => id}, _session, socket) do
    family = Families.get_family!(family_id)
    person = People.get_person!(id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, person)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}
end
