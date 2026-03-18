defmodule Web.FamilyLive.SidePanelComponent do
  use Web, :live_component

  alias Web.FamilyLive.GalleryListComponent
  alias Web.FamilyLive.PeopleListComponent

  @impl true
  def render(assigns) do
    ~H"""
    <aside
      id={@id}
      class={[
        "border-l border-base-200 bg-base-100 flex flex-col p-4 gap-6",
        "w-72 lg:w-72",
        "max-lg:w-full max-lg:border-l-0 max-lg:border-t"
      ]}
    >
      <.live_component
        module={GalleryListComponent}
        id="gallery-list"
        galleries={@galleries}
        family_id={@family_id}
      />

      <div class="border-t border-base-200"></div>

      <.live_component
        module={PeopleListComponent}
        id="people-list"
        people={@people}
        family_id={@family_id}
        focus_person_id={@focus_person_id}
      />
    </aside>
    """
  end
end
