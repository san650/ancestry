defmodule Web.Shared.AddRelationshipComponent do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def update(%{person_created: person}, socket) do
    person = People.get_person!(person.id)
    relationship_form = build_relationship_form(socket.assigns.relationship_type, person)

    {:ok,
     socket
     |> assign(:step, :metadata)
     |> assign(:selected_person, person)
     |> assign(:relationship_form, relationship_form)}
  end

  def update(%{cancelled: true}, socket) do
    {:ok, assign(socket, :step, :search)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:person, assigns.person)
     |> assign(:family, assigns.family)
     |> assign(:relationship_type, assigns.relationship_type)
     |> assign(:partner_id, Map.get(assigns, :partner_id))
     |> assign_new(:step, fn -> :choose end)
     |> assign_new(:search_query, fn -> "" end)
     |> assign_new(:search_results, fn -> [] end)
     |> assign_new(:selected_person, fn -> nil end)
     |> assign_new(:relationship_form, fn -> nil end)
     |> assign_new(:quick_create_prefill_name, fn -> nil end)}
  end

  # -------------------------------------------------------------------
  # Event handlers
  # -------------------------------------------------------------------

  @impl true
  def handle_event(
        "search_members",
        %{"value" => query},
        %{assigns: %{family: %{id: family_id}}} = socket
      ) do
    results =
      if String.length(query) >= 2 do
        People.search_family_members(query, family_id, socket.assigns.person.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("search_members", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        People.search_all_people(
          query,
          socket.assigns.person.id,
          socket.assigns.current_scope.organization.id
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

  def handle_event("start_search", _, socket) do
    {:noreply,
     socket
     |> assign(:step, :search)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  def handle_event("start_quick_create", _, socket) do
    prefill =
      case String.trim(socket.assigns.search_query) do
        "" -> nil
        query -> query
      end

    {:noreply,
     socket
     |> assign(:step, :quick_create)
     |> assign(:quick_create_prefill_name, prefill)}
  end

  def handle_event("back_to_choose", _, socket) do
    {:noreply,
     socket
     |> assign(:step, :choose)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_person, nil)
     |> assign(:quick_create_prefill_name, nil)}
  end

  def handle_event("validate_partner_form", %{"metadata" => metadata_params}, socket) do
    {:noreply, assign(socket, :relationship_form, to_form(metadata_params, as: :metadata))}
  end

  def handle_event("save_relationship", params, socket) do
    person = socket.assigns.person
    selected = socket.assigns.selected_person
    type = socket.assigns.relationship_type

    result =
      case type do
        "parent" ->
          metadata_params = Map.get(params, "metadata", %{})
          role = Map.get(metadata_params, "role")

          # Default gender based on role (father → male, mother → female)
          maybe_set_gender_from_role(selected, role)

          case Relationships.create_relationship(
                 selected,
                 person,
                 "parent",
                 atomize_metadata(metadata_params)
               ) do
            {:ok, _} = ok ->
              # Auto-create partner relationship with existing co-parent
              maybe_link_coparents(selected, person)
              ok

            error ->
              error
          end

        "partner" ->
          metadata_params = Map.get(params, "metadata", %{})
          partner_subtype = Map.get(metadata_params, "partner_subtype", "relationship")
          clean_metadata = Map.delete(metadata_params, "partner_subtype")

          Relationships.create_relationship(
            person,
            selected,
            partner_subtype,
            atomize_metadata(clean_metadata)
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
        <h2 class="text-xl font-ds-heading font-bold text-ds-on-surface">
          {relationship_title(@relationship_type)}
        </h2>
        <button
          phx-click="cancel_add_relationship"
          class="p-2 rounded-ds-sharp text-ds-on-surface-variant/50 hover:text-ds-on-surface hover:bg-ds-surface-highest transition-all"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <%= case @step do %>
        <% :choose -> %>
          <div class="space-y-3">
            <p class="text-sm text-ds-on-surface-variant">
              {gettext("Add a relationship by linking an existing person or creating a new one.")}
            </p>
            <button
              id="add-rel-link-existing-btn"
              type="button"
              phx-click="start_search"
              phx-target={@myself}
              class="w-full flex items-center gap-3 p-4 rounded-ds-sharp bg-ds-surface-low hover:bg-ds-surface-highest transition-colors text-left"
            >
              <.icon name="hero-magnifying-glass" class="w-5 h-5 text-ds-primary shrink-0" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-ds-body font-semibold text-ds-on-surface">
                  {gettext("Link existing person")}
                </p>
                <p class="text-xs text-ds-on-surface-variant">
                  {gettext("Search for someone already in this organization.")}
                </p>
              </div>
            </button>
            <button
              id="add-rel-create-new-btn"
              type="button"
              phx-click="start_quick_create"
              phx-target={@myself}
              class="w-full flex items-center gap-3 p-4 rounded-ds-sharp bg-ds-surface-low hover:bg-ds-surface-highest transition-colors text-left"
            >
              <.icon name="hero-plus" class="w-5 h-5 text-ds-primary shrink-0" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-ds-body font-semibold text-ds-on-surface">
                  {gettext("Create new person")}
                </p>
                <p class="text-xs text-ds-on-surface-variant">
                  {gettext("Add someone who isn't in the system yet.")}
                </p>
              </div>
            </button>
          </div>
        <% :search -> %>
          <div class="space-y-4">
            <button
              id="add-rel-back-to-choose-from-search-btn"
              type="button"
              phx-click="back_to_choose"
              phx-target={@myself}
              class="flex items-center gap-1 text-sm text-ds-primary/70 hover:text-ds-primary mb-3 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> {gettext("Back")}
            </button>
            <p class="text-sm text-ds-on-surface-variant">
              {gettext("Search for a person to add as a relationship.")}
            </p>
            <input
              id="relationship-search-input"
              type="text"
              placeholder={gettext("Type a name to search...")}
              value={@search_query}
              phx-keyup="search_members"
              phx-target={@myself}
              phx-debounce="300"
              class="bg-ds-surface-card border border-ds-outline-variant/20 rounded-ds-sharp px-3 py-2 text-sm text-ds-on-surface w-full"
              autocomplete="off"
            />

            <%= if @search_results != [] do %>
              <div class="space-y-0.5 max-h-44 overflow-y-auto" id="add-relationship-search-results">
                <%= for result <- @search_results do %>
                  <button
                    id={"search-result-#{result.id}"}
                    type="button"
                    phx-click="select_person"
                    phx-target={@myself}
                    phx-value-id={result.id}
                    class="w-full flex items-center gap-2 px-2 py-1.5 rounded-ds-sharp hover:bg-ds-surface-highest transition-colors text-left"
                  >
                    <div class="w-6 h-6 rounded-full bg-ds-primary/10 flex items-center justify-center overflow-hidden flex-shrink-0">
                      <%= if result.photo && result.photo_status == "processed" do %>
                        <img
                          src={Ancestry.Uploaders.PersonPhoto.url({result.photo, result}, :thumbnail)}
                          alt={Person.display_name(result)}
                          class="w-full h-full object-cover"
                        />
                      <% else %>
                        <.icon name="hero-user" class="w-3 h-3 text-ds-primary" />
                      <% end %>
                    </div>
                    <span class="text-sm text-ds-on-surface truncate">
                      {Person.display_name(result)}
                    </span>
                  </button>
                <% end %>
              </div>
            <% else %>
              <%= if String.length(@search_query) >= 2 do %>
                <p class="text-sm text-ds-on-surface-variant text-center py-4">
                  {gettext("No results found")}
                </p>
              <% end %>
            <% end %>
          </div>
        <% :quick_create -> %>
          <div id="quick-create-person">
            <button
              id="add-rel-back-to-choose-from-quick-create-btn"
              phx-click="back_to_choose"
              phx-target={@myself}
              class="flex items-center gap-1 text-sm text-ds-primary/70 hover:text-ds-primary mb-4 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> {gettext("Back")}
            </button>

            <.live_component
              module={Web.Shared.QuickPersonModal}
              id="quick-person-modal-relationship"
              show_acquaintance={false}
              show_modal_wrapper={false}
              organization_id={@family.organization_id}
              family_id={@family.id}
              prefill_name={@quick_create_prefill_name}
            />
          </div>
        <% :metadata -> %>
          <div class="space-y-4">
            <div class="rounded-ds-sharp bg-ds-surface-low/50 p-3">
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
                      label={gettext("Role")}
                      options={[{gettext("Father"), "father"}, {gettext("Mother"), "mother"}]}
                    />
                    <button
                      type="submit"
                      class="w-full bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
                    >
                      Add Parent
                    </button>
                  </div>
                </.form>
              <% @relationship_type == "partner" && @relationship_form -> %>
                <.form
                  for={@relationship_form}
                  id="add-partner-form"
                  phx-target={@myself}
                  phx-change="validate_partner_form"
                  phx-submit="save_relationship"
                >
                  <div class="space-y-4">
                    <.input
                      field={@relationship_form[:partner_subtype]}
                      type="select"
                      label={gettext("Status")}
                      options={[
                        {gettext("In a relationship"), "relationship"},
                        {gettext("Married"), "married"},
                        {gettext("Divorced"), "divorced"},
                        {gettext("Separated"), "separated"}
                      ]}
                    />
                    <% subtype =
                      Phoenix.HTML.Form.input_value(@relationship_form, :partner_subtype) %>
                    <%= if subtype in ~w(married divorced separated) do %>
                      <p class="text-sm font-ds-body font-medium text-ds-on-surface-variant">
                        {gettext("Marriage Details (optional)")}
                      </p>
                      <div class="grid grid-cols-3 gap-3">
                        <.input
                          field={@relationship_form[:marriage_day]}
                          type="number"
                          placeholder={gettext("Day")}
                          label={gettext("Day")}
                        />
                        <.input
                          field={@relationship_form[:marriage_month]}
                          type="number"
                          placeholder={gettext("Month")}
                          label={gettext("Month")}
                        />
                        <.input
                          field={@relationship_form[:marriage_year]}
                          type="number"
                          placeholder={gettext("Year")}
                          label={gettext("Year")}
                        />
                      </div>
                      <.input
                        field={@relationship_form[:marriage_location]}
                        type="text"
                        label={gettext("Location")}
                        placeholder={gettext("e.g. London, UK")}
                      />
                    <% end %>
                    <button
                      type="submit"
                      class="w-full bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
                    >
                      Add Partner
                    </button>
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
                  <button
                    type="submit"
                    class="w-full bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
                  >
                    Add Child
                  </button>
                </.form>
              <% true -> %>
                <p class="text-sm text-ds-on-surface-variant">
                  {gettext("Unknown relationship type.")}
                </p>
            <% end %>

            <button
              phx-click="cancel_add_relationship"
              class="w-full bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
            >
              {gettext("Cancel")}
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
      "flex items-center gap-3 p-2 rounded-ds-sharp",
      @highlighted && "bg-ds-primary/10 border border-ds-primary/20"
    ]}>
      <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-ds-surface-low">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-5 h-5 text-ds-on-surface-variant/50" />
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-ds-body font-medium text-sm text-ds-on-surface truncate">
          {Person.display_name(@person)}
        </p>
        <p class="text-xs text-ds-on-surface-variant">
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
        to_form(%{"partner_subtype" => "relationship"}, as: :metadata)

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
    params
    |> Map.delete("partner_subtype")
    |> Map.new(fn {k, v} ->
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
               :divorce_year,
               :separated_day,
               :separated_month,
               :separated_year
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

  defp relationship_title("parent"), do: gettext("Add Parent")
  defp relationship_title("partner"), do: gettext("Add Partner")
  defp relationship_title("child"), do: gettext("Add Child")
  defp relationship_title("child_solo"), do: gettext("Add Child (Unknown Other Parent)")
  defp relationship_title(_), do: gettext("Add Relationship")

  # Set gender on a person based on parent role (father → male, mother → female).
  # Only updates if the person has no gender set yet.
  defp maybe_set_gender_from_role(%Person{gender: nil} = person, "father") do
    People.update_person(person, %{gender: "male"})
  end

  defp maybe_set_gender_from_role(%Person{gender: nil} = person, "mother") do
    People.update_person(person, %{gender: "female"})
  end

  defp maybe_set_gender_from_role(_person, _role), do: :ok

  # After adding a parent, check if the child already has another parent.
  # If so, create a "relationship" between the two parents (unless one already exists).
  defp maybe_link_coparents(new_parent, child) do
    case Ancestry.Relationships.get_parents(child.id) do
      parents when length(parents) == 2 ->
        [{p1, _}, {p2, _}] = parents
        other = if p1.id == new_parent.id, do: p2, else: p1

        # Only create if no partner relationship exists yet
        existing = Ancestry.Relationships.list_relationships_for_person(new_parent.id)

        has_partner_rel =
          Enum.any?(existing, fn r ->
            r.type in ~w(married relationship divorced separated) and
              (r.person_a_id == other.id or r.person_b_id == other.id)
          end)

        unless has_partner_rel do
          Relationships.create_relationship(new_parent, other, "relationship", %{})
        end

      _ ->
        :ok
    end
  end

  defp relationship_error_message(:max_parents_reached),
    do: gettext("This person already has 2 parents")

  defp relationship_error_message(:partner_relationship_exists),
    do: gettext("A partner relationship already exists between these two people")

  defp relationship_error_message(%Ecto.Changeset{}), do: gettext("Invalid relationship data")
  defp relationship_error_message(_), do: gettext("Failed to create relationship")
end
