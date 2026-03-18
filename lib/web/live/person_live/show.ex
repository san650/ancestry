defmodule Web.PersonLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.Relationships

  @impl true
  def mount(%{"family_id" => family_id, "id" => id}, _session, socket) do
    family = Families.get_family!(family_id)
    person = People.get_person!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, person)
     |> assign(:editing, false)
     |> assign(:confirm_remove, false)
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(People.change_person(person)))
     |> load_relationships(person)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("edit", _, socket) do
    form = to_form(People.change_person(socket.assigns.person))
    {:noreply, socket |> assign(:editing, true) |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params = process_alternate_names(params)

    case People.update_person(socket.assigns.person, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)

        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:editing, false)
         |> assign(:form, to_form(People.change_person(person)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
  end

  def handle_event("cancel_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, false)}
  end

  def handle_event("confirm_remove", _, socket) do
    family = socket.assigns.family
    person = socket.assigns.person
    {:ok, _} = People.remove_from_family(person, family)
    {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}")}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    family = socket.assigns.family
    {:ok, _} = People.delete_person(socket.assigns.person)
    {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}")}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  # --- Relationship event handlers (Task 10) ---

  def handle_event("add_relationship", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, type)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_person, nil)
     |> assign(:relationship_form, nil)
     |> assign(:adding_partner_id, nil)
     |> assign(:quick_creating, false)}
  end

  def handle_event("add_child_for_partner", %{"partner-id" => partner_id}, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, "child")
     |> assign(:adding_partner_id, String.to_integer(partner_id))
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_person, nil)
     |> assign(:relationship_form, nil)
     |> assign(:quick_creating, false)}
  end

  def handle_event("cancel_add_relationship", _, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, nil)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_person, nil)
     |> assign(:relationship_form, nil)
     |> assign(:adding_partner_id, nil)
     |> assign(:quick_creating, false)}
  end

  def handle_event("start_quick_create", _, socket) do
    {:noreply, assign(socket, :quick_creating, true)}
  end

  def handle_event("cancel_quick_create", _, socket) do
    {:noreply, assign(socket, :quick_creating, false)}
  end

  def handle_event("search_members", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        People.search_family_members(query, socket.assigns.family.id, socket.assigns.person.id)
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
    type = socket.assigns.adding_relationship

    relationship_form =
      case type do
        "parent" ->
          role = if selected.gender == "male", do: "father", else: "mother"
          to_form(%{"role" => role}, as: :metadata)

        "partner" ->
          to_form(%{}, as: :metadata)

        _ ->
          nil
      end

    {:noreply,
     socket
     |> assign(:selected_person, selected)
     |> assign(:relationship_form, relationship_form)}
  end

  def handle_event("save_relationship", params, socket) do
    person = socket.assigns.person
    selected = socket.assigns.selected_person
    type = socket.assigns.adding_relationship

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
              partner_id = socket.assigns.adding_partner_id

              if partner_id do
                partner = People.get_person!(partner_id)
                partner_role = if partner.gender == "male", do: "father", else: "mother"

                case Relationships.create_relationship(partner, selected, "parent", %{
                       role: partner_role
                     }) do
                  {:ok, _} -> :ok
                  {:error, _} -> :ok
                end
              end

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
        {:noreply,
         socket
         |> load_relationships(person)
         |> assign(:adding_relationship, nil)
         |> assign(:search_query, "")
         |> assign(:search_results, [])
         |> assign(:selected_person, nil)
         |> assign(:relationship_form, nil)
         |> assign(:adding_partner_id, nil)
         |> put_flash(:info, "Relationship added")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, relationship_error_message(reason))}
    end
  end

  def handle_event("convert_to_ex", %{"id" => rel_id}, socket) do
    rel = Ancestry.Repo.get!(Ancestry.Relationships.Relationship, rel_id)

    {:noreply,
     socket
     |> assign(:converting_to_ex, rel)
     |> assign(:ex_form, to_form(%{}, as: :divorce))}
  end

  def handle_event("cancel_convert_to_ex", _, socket) do
    {:noreply,
     socket
     |> assign(:converting_to_ex, nil)
     |> assign(:ex_form, nil)}
  end

  def handle_event("save_convert_to_ex", %{"divorce" => divorce_params}, socket) do
    rel = socket.assigns.converting_to_ex

    divorce_attrs =
      divorce_params
      |> atomize_metadata()

    case Relationships.convert_to_ex_partner(rel, divorce_attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_relationships(socket.assigns.person)
         |> assign(:converting_to_ex, nil)
         |> assign(:ex_form, nil)
         |> put_flash(:info, "Marked as ex-partner")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to convert to ex-partner")}
    end
  end

  def handle_event("edit_relationship", %{"id" => rel_id}, socket) do
    rel = Ancestry.Repo.get!(Ancestry.Relationships.Relationship, rel_id)

    form_data =
      case rel.type do
        "parent" ->
          %{
            "role" => rel.metadata && rel.metadata.role
          }

        "partner" ->
          %{
            "marriage_day" => rel.metadata && rel.metadata.marriage_day,
            "marriage_month" => rel.metadata && rel.metadata.marriage_month,
            "marriage_year" => rel.metadata && rel.metadata.marriage_year,
            "marriage_location" => rel.metadata && rel.metadata.marriage_location
          }

        "ex_partner" ->
          %{
            "marriage_day" => rel.metadata && rel.metadata.marriage_day,
            "marriage_month" => rel.metadata && rel.metadata.marriage_month,
            "marriage_year" => rel.metadata && rel.metadata.marriage_year,
            "marriage_location" => rel.metadata && rel.metadata.marriage_location,
            "divorce_day" => rel.metadata && rel.metadata.divorce_day,
            "divorce_month" => rel.metadata && rel.metadata.divorce_month,
            "divorce_year" => rel.metadata && rel.metadata.divorce_year
          }
      end

    {:noreply,
     socket
     |> assign(:editing_relationship, rel)
     |> assign(:edit_relationship_form, to_form(form_data, as: :metadata))}
  end

  def handle_event("cancel_edit_relationship", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_relationship, nil)
     |> assign(:edit_relationship_form, nil)}
  end

  def handle_event("save_edit_relationship", %{"metadata" => metadata_params}, socket) do
    rel = socket.assigns.editing_relationship

    attrs = %{
      metadata: Map.put(atomize_metadata(metadata_params), :__type__, rel.type)
    }

    case Relationships.update_relationship(rel, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_relationships(socket.assigns.person)
         |> assign(:editing_relationship, nil)
         |> assign(:edit_relationship_form, nil)
         |> put_flash(:info, "Relationship updated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update relationship")}
    end
  end

  def handle_event("delete_relationship", %{"id" => rel_id}, socket) do
    rel = Ancestry.Repo.get!(Ancestry.Relationships.Relationship, rel_id)

    case Relationships.delete_relationship(rel) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_relationships(socket.assigns.person)
         |> put_flash(:info, "Relationship removed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove relationship")}
    end
  end

  @impl true
  def handle_info({:person_photo_processed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  def handle_info({:person_photo_failed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  def handle_info({:person_created, person, type}, socket) do
    relationship_form =
      case type do
        "parent" ->
          role = if person.gender == "male", do: "father", else: "mother"
          to_form(%{"role" => role}, as: :metadata)

        "partner" ->
          to_form(%{}, as: :metadata)

        _ ->
          nil
      end

    {:noreply,
     socket
     |> assign(:quick_creating, false)
     |> assign(:selected_person, person)
     |> assign(:relationship_form, relationship_form)}
  end

  # --- Private helpers ---

  defp load_relationships(socket, person) do
    partners = Relationships.get_partners(person.id)
    ex_partners = Relationships.get_ex_partners(person.id)
    all_partner_rels = partners ++ ex_partners

    children_with_coparents = Relationships.get_children_with_coparents(person.id)

    partner_ids = MapSet.new(all_partner_rels, fn {p, _rel} -> p.id end)

    # Group children into three buckets
    {partner_child_map, coparent_map, solo_children} =
      Enum.reduce(children_with_coparents, {%{}, %{}, []}, fn
        {child, nil}, {pc, cp, solo} ->
          {pc, cp, [child | solo]}

        {child, coparent}, {pc, cp, solo} ->
          if MapSet.member?(partner_ids, coparent.id) do
            {Map.update(pc, coparent.id, [child], &[child | &1]), cp, solo}
          else
            {pc,
             Map.update(cp, coparent.id, {coparent, [child]}, fn {cp_person, kids} ->
               {cp_person, [child | kids]}
             end), solo}
          end
      end)

    # Attach children to partner tuples
    partner_children =
      Enum.map(all_partner_rels, fn {partner, rel} ->
        children = partner_child_map |> Map.get(partner.id, []) |> Enum.reverse()
        {partner, rel, children}
      end)

    # Convert coparent map to list of {coparent, [children]}
    coparent_children =
      coparent_map
      |> Map.values()
      |> Enum.map(fn {coparent, children} -> {coparent, Enum.reverse(children)} end)

    parents = Relationships.get_parents(person.id)

    parents_marriage =
      case parents do
        [{p1, _}, {p2, _}] ->
          case Relationships.get_partners(p1.id) do
            partners ->
              Enum.find_value(partners, fn {partner, rel} ->
                if partner.id == p2.id, do: rel
              end)
          end

        _ ->
          nil
      end

    socket
    |> assign(:parents, parents)
    |> assign(:parents_marriage, parents_marriage)
    |> assign(:partner_children, partner_children)
    |> assign(:coparent_children, coparent_children)
    |> assign(:siblings, Relationships.get_siblings(person.id))
    |> assign(:solo_children, Enum.reverse(solo_children))
    |> assign(:adding_relationship, nil)
    |> assign(:search_query, "")
    |> assign(:search_results, [])
    |> assign(:selected_person, nil)
    |> assign(:relationship_form, nil)
    |> assign(:converting_to_ex, nil)
    |> assign(:ex_form, nil)
    |> assign(:editing_relationship, nil)
    |> assign(:edit_relationship_form, nil)
    |> assign(:adding_partner_id, nil)
    |> assign(:quick_creating, false)
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

  defp relationship_error_message(:max_parents_reached), do: "This person already has 2 parents"
  defp relationship_error_message(%Ecto.Changeset{}), do: "Invalid relationship data"
  defp relationship_error_message(_), do: "Failed to create relationship"

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} ->
        params

      {"", params} ->
        params

      {text, params} ->
        names =
          text
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "alternate_names", names)
    end
  end

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end

  defp format_partial_date(day, month, year) do
    [day, month, year]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      parts -> Enum.join(parts, "/")
    end
  end

  defp format_marriage_info(metadata) do
    date =
      format_partial_date(metadata.marriage_day, metadata.marriage_month, metadata.marriage_year)

    location = metadata.marriage_location

    parts =
      [date, location]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    if parts == [], do: nil, else: Enum.join(parts, " - ")
  end

  defp sibling_type(sibling_tuple) do
    case sibling_tuple do
      {_person, _pa, _pb} -> :full
      {_person, _shared} -> :half
    end
  end

  defp sibling_person(sibling_tuple) do
    elem(sibling_tuple, 0)
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp person_card(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 p-2 rounded-lg",
      @highlighted && "bg-primary/10 border border-primary/20"
    ]}>
      <div class="w-10 h-10 rounded-full shrink-0 flex items-center justify-center overflow-hidden bg-base-200">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Ancestry.People.Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-5 h-5 text-base-content/20" />
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-medium text-sm text-base-content truncate">
          {Ancestry.People.Person.display_name(@person)}
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

  defp add_relationship_title("parent"), do: "Add Parent"
  defp add_relationship_title("partner"), do: "Add Spouse/Partner"
  defp add_relationship_title("child"), do: "Add Child"
  defp add_relationship_title("child_solo"), do: "Add Child (Unknown Other Parent)"
  defp add_relationship_title(_), do: "Add Relationship"
end
