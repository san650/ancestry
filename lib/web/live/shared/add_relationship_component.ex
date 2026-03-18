defmodule Web.Shared.AddRelationshipComponent do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:person, assigns.person)
     |> assign(:family, assigns.family)
     |> assign(:relationship_type, assigns.relationship_type)
     |> assign(:partner_id, Map.get(assigns, :partner_id))
     |> assign_new(:step, fn -> :search end)
     |> assign_new(:search_query, fn -> "" end)
     |> assign_new(:search_results, fn -> [] end)
     |> assign_new(:selected_person, fn -> nil end)
     |> assign_new(:relationship_form, fn -> nil end)
     |> assign_new(:person_form, fn ->
       to_form(People.change_person(%Person{}), as: :person)
     end)}
  end

  # -------------------------------------------------------------------
  # Event handlers
  # -------------------------------------------------------------------

  @impl true
  def handle_event("search_members", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        People.search_family_members(
          query,
          socket.assigns.family.id,
          socket.assigns.person.id
        )
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("select_person", %{"id" => person_id}, socket) do
    selected = People.get_person!(person_id)
    relationship_form = build_relationship_form(socket.assigns.relationship_type, selected)

    {:noreply,
     socket
     |> assign(:selected_person, selected)
     |> assign(:relationship_form, relationship_form)
     |> assign(:step, :metadata)}
  end

  def handle_event("start_quick_create", _, socket) do
    {:noreply,
     socket
     |> assign(:step, :quick_create)
     |> assign(:person_form, to_form(People.change_person(%Person{}), as: :person))}
  end

  def handle_event("cancel_quick_create", _, socket) do
    {:noreply, assign(socket, :step, :search)}
  end

  def handle_event("validate_person", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :person_form, to_form(changeset, as: :person))}
  end

  def handle_event("save_person", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Ecto.Changeset.validate_required([:given_name])

    if changeset.valid? do
      case People.create_person(socket.assigns.family, params) do
        {:ok, person} ->
          person = People.get_person!(person.id)
          relationship_form = build_relationship_form(socket.assigns.relationship_type, person)

          {:noreply,
           socket
           |> assign(:step, :metadata)
           |> assign(:selected_person, person)
           |> assign(:relationship_form, relationship_form)}

        {:error, changeset} ->
          {:noreply, assign(socket, :person_form, to_form(changeset, as: :person))}
      end
    else
      {:noreply,
       assign(socket, :person_form, to_form(%{changeset | action: :validate}, as: :person))}
    end
  end

  def handle_event("save_relationship", params, socket) do
    person = socket.assigns.person
    selected = socket.assigns.selected_person
    type = socket.assigns.relationship_type

    result =
      case type do
        "parent" ->
          metadata_params = Map.get(params, "metadata", %{})

          Relationships.create_relationship(
            selected,
            person,
            "parent",
            atomize_metadata(metadata_params)
          )

        "partner" ->
          metadata_params = Map.get(params, "metadata", %{})

          Relationships.create_relationship(
            person,
            selected,
            "partner",
            atomize_metadata(metadata_params)
          )

        "child" ->
          role = if person.gender == "male", do: "father", else: "mother"

          case Relationships.create_relationship(person, selected, "parent", %{role: role}) do
            {:ok, _} = ok ->
              maybe_add_coparent(socket.assigns.partner_id, selected, socket)
              ok

            error ->
              error
          end

        "child_solo" ->
          role = if person.gender == "male", do: "father", else: "mother"
          Relationships.create_relationship(person, selected, "parent", %{role: role})
      end

    case result do
      {:ok, _} ->
        send(self(), {:relationship_saved, type, selected})
        {:noreply, socket}

      {:error, reason} ->
        send(self(), {:relationship_error, relationship_error_message(reason)})
        {:noreply, socket}
    end
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id="add-relationship-component">
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-xl font-bold text-base-content">
          {relationship_title(@relationship_type)}
        </h2>
        <button
          phx-click="cancel_add_relationship"
          class="p-2 rounded-lg text-base-content/30 hover:text-base-content hover:bg-base-200 transition-all"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <%= case @step do %>
        <% :search -> %>
          <div class="space-y-4">
            <p class="text-sm text-base-content/60">
              Search for an existing family member to add as a relationship.
            </p>
            <input
              id="relationship-search-input"
              type="text"
              placeholder="Type a name to search..."
              value={@search_query}
              phx-keyup="search_members"
              phx-target={@myself}
              phx-debounce="300"
              class="input input-bordered w-full"
              autocomplete="off"
            />

            <%= if @search_results != [] do %>
              <div class="space-y-1 max-h-60 overflow-y-auto">
                <%= for result <- @search_results do %>
                  <button
                    id={"search-result-#{result.id}"}
                    phx-click="select_person"
                    phx-target={@myself}
                    phx-value-id={result.id}
                    class="w-full text-left rounded-lg transition-colors hover:bg-base-200"
                  >
                    <.person_card_inline person={result} highlighted={false} />
                  </button>
                <% end %>
              </div>
            <% else %>
              <%= if String.length(@search_query) >= 2 do %>
                <p class="text-sm text-base-content/40 text-center py-4">
                  No results found
                </p>
              <% end %>
            <% end %>

            <button
              id="start-quick-create-btn"
              phx-click="start_quick_create"
              phx-target={@myself}
              class="flex items-center gap-1.5 text-sm text-primary/70 hover:text-primary w-full justify-center py-2 border-t border-base-200 mt-2 transition-colors"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Person not listed? Create new
            </button>
          </div>
        <% :quick_create -> %>
          <div id="quick-create-person">
            <button
              id="cancel-quick-create-btn"
              phx-click="cancel_quick_create"
              phx-target={@myself}
              class="flex items-center gap-1 text-sm text-primary/70 hover:text-primary mb-4 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to search
            </button>

            <p class="text-sm text-base-content/60 mb-4">
              Create a new person to add as a relationship.
            </p>

            <.form
              for={@person_form}
              id="quick-create-person-form"
              phx-target={@myself}
              phx-change="validate_person"
              phx-submit="save_person"
            >
              <div class="space-y-4">
                <.input field={@person_form[:given_name]} label="Given name" />
                <.input field={@person_form[:surname]} label="Surname" />
                <button type="submit" class="btn btn-primary w-full">
                  Create &amp; Continue
                </button>
              </div>
            </.form>
          </div>
        <% :metadata -> %>
          <div class="space-y-4">
            <div class="rounded-lg bg-base-200/50 p-3">
              <.person_card_inline person={@selected_person} highlighted={true} />
            </div>

            <%= cond do %>
              <% @relationship_type == "parent" && @relationship_form -> %>
                <.form
                  for={@relationship_form}
                  id="add-parent-form"
                  phx-target={@myself}
                  phx-submit="save_relationship"
                >
                  <div class="space-y-4">
                    <.input
                      field={@relationship_form[:role]}
                      type="select"
                      label="Role"
                      options={[{"Father", "father"}, {"Mother", "mother"}]}
                    />
                    <button type="submit" class="btn btn-primary w-full">Add Parent</button>
                  </div>
                </.form>
              <% @relationship_type == "partner" && @relationship_form -> %>
                <.form
                  for={@relationship_form}
                  id="add-partner-form"
                  phx-target={@myself}
                  phx-submit="save_relationship"
                >
                  <div class="space-y-4">
                    <p class="text-sm font-medium text-base-content/60">
                      Marriage Details (optional)
                    </p>
                    <div class="grid grid-cols-3 gap-3">
                      <.input
                        field={@relationship_form[:marriage_day]}
                        type="number"
                        placeholder="Day"
                        label="Day"
                      />
                      <.input
                        field={@relationship_form[:marriage_month]}
                        type="number"
                        placeholder="Month"
                        label="Month"
                      />
                      <.input
                        field={@relationship_form[:marriage_year]}
                        type="number"
                        placeholder="Year"
                        label="Year"
                      />
                    </div>
                    <.input
                      field={@relationship_form[:marriage_location]}
                      type="text"
                      label="Location"
                      placeholder="e.g. London, UK"
                    />
                    <button type="submit" class="btn btn-primary w-full">Add Spouse</button>
                  </div>
                </.form>
              <% @relationship_type in ["child", "child_solo"] -> %>
                <.form
                  for={%{}}
                  as={:metadata}
                  id="add-child-form"
                  phx-target={@myself}
                  phx-submit="save_relationship"
                >
                  <button type="submit" class="btn btn-primary w-full">Add Child</button>
                </.form>
              <% true -> %>
                <p class="text-sm text-base-content/40">Unknown relationship type.</p>
            <% end %>

            <button
              phx-click="cancel_add_relationship"
              class="btn btn-ghost w-full"
            >
              Cancel
            </button>
          </div>
      <% end %>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private components
  # -------------------------------------------------------------------

  defp person_card_inline(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 p-2 rounded-lg",
      @highlighted && "bg-primary/10 border border-primary/20"
    ]}>
      <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-base-200">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-5 h-5 text-base-content/20" />
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-medium text-sm text-base-content truncate">
          {Person.display_name(@person)}
        </p>
        <p class="text-xs text-base-content/50">
          <%= if @person.birth_year do %>
            {@person.birth_year}
          <% end %>
          <%= if @person.birth_year && @person.deceased do %>
            -
          <% end %>
          <%= if @person.deceased do %>
            <span title="This person is deceased.">
              {if @person.death_year, do: "d. #{@person.death_year}", else: "deceased"}
            </span>
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp build_relationship_form(type, selected_person) do
    case type do
      "parent" ->
        role = if selected_person.gender == "male", do: "father", else: "mother"
        to_form(%{"role" => role}, as: :metadata)

      "partner" ->
        to_form(%{}, as: :metadata)

      _ ->
        nil
    end
  end

  defp maybe_add_coparent(nil, _child, _socket), do: :ok

  defp maybe_add_coparent(partner_id, child, _socket) do
    partner = People.get_person!(partner_id)
    partner_role = if partner.gender == "male", do: "father", else: "mother"

    case Relationships.create_relationship(partner, child, "parent", %{role: partner_role}) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp atomize_metadata(params) do
    Map.new(params, fn {k, v} ->
      key =
        if is_binary(k) do
          String.to_existing_atom(k)
        else
          k
        end

      val =
        if is_binary(v) and v != "" and
             key in [
               :marriage_day,
               :marriage_month,
               :marriage_year,
               :divorce_day,
               :divorce_month,
               :divorce_year
             ] do
          case Integer.parse(v) do
            {int, ""} -> int
            _ -> v
          end
        else
          v
        end

      {key, val}
    end)
  end

  defp relationship_title("parent"), do: "Add Parent"
  defp relationship_title("partner"), do: "Add Spouse/Partner"
  defp relationship_title("child"), do: "Add Child"
  defp relationship_title("child_solo"), do: "Add Child (Unknown Other Parent)"
  defp relationship_title(_), do: "Add Relationship"

  defp relationship_error_message(:max_parents_reached), do: "This person already has 2 parents"
  defp relationship_error_message(%Ecto.Changeset{}), do: "Invalid relationship data"
  defp relationship_error_message(_), do: "Failed to create relationship"
end
