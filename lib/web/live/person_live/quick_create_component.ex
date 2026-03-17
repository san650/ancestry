defmodule Web.PersonLive.QuickCreateComponent do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:family, assigns.family)
     |> assign(:relationship_type, assigns.relationship_type)
     |> assign_new(:form, fn -> to_form(People.change_person(%Person{}), as: :person) end)}
  end

  @impl true
  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Ecto.Changeset.validate_required([:given_name])

    if changeset.valid? do
      case People.create_person(socket.assigns.family, params) do
        {:ok, person} ->
          person = People.get_person!(person.id)
          send(self(), {:person_created, person, socket.assigns.relationship_type})
          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
      end
    else
      {:noreply, assign(socket, :form, to_form(%{changeset | action: :validate}, as: :person))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="quick-create-person">
      <button
        id="cancel-quick-create-btn"
        phx-click="cancel_quick_create"
        class="flex items-center gap-1 text-sm text-primary/70 hover:text-primary mb-4 transition-colors"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to search
      </button>

      <p class="text-sm text-base-content/60 mb-4">
        Create a new person to add as a relationship.
      </p>

      <.form
        for={@form}
        id="quick-create-person-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input field={@form[:given_name]} label="Given name" />
          <.input field={@form[:surname]} label="Surname" />
          <button type="submit" class="btn btn-primary w-full">
            Create &amp; Continue
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
