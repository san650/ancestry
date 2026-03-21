defmodule Web.PersonLive.Show do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.People
  alias Ancestry.Relationships
  alias Web.PhotoInteractions

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    person = People.get_person!(id)

    if person.organization_id != socket.assigns.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.People.Person
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")
    end

    {:ok,
     socket
     |> assign(:person, person)
     |> assign(:from_family, nil)
     |> assign(:editing, false)
     |> assign(:confirm_remove, false)
     |> assign(:confirm_delete, false)
     |> assign(:selected_photo, nil)
     |> assign(:panel_open, false)
     |> assign(:photo_people, [])
     |> assign(:comments_topic, nil)
     |> load_relationships(person)
     |> load_person_photos(person)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    from_family =
      case params do
        %{"from_family" => family_id} -> Families.get_family!(family_id)
        _ -> nil
      end

    socket =
      socket
      |> assign(:from_family, from_family)
      |> maybe_enter_edit_mode(params["edit"] == "true")

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit", _, socket) do
    {:noreply, enter_edit_mode(socket)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("toggle_details", _, socket) do
    {:noreply, assign(socket, :show_details, true)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    params = invert_living_to_deceased(params)

    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params =
      params
      |> invert_living_to_deceased()
      |> process_alternate_names()

    case People.update_person(socket.assigns.person, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)

        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:editing, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("remove_photo", _, socket) do
    case People.remove_photo(socket.assigns.person) do
      {:ok, person} ->
        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:form, to_form(People.change_person(person)))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove photo")}
    end
  end

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
  end

  def handle_event("cancel_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, false)}
  end

  def handle_event("confirm_remove", _, socket) do
    person = socket.assigns.person
    family = socket.assigns.from_family
    {:ok, _} = People.remove_from_family(person, family)

    {:noreply,
     push_navigate(socket, to: ~p"/org/#{socket.assigns.organization.id}/families/#{family.id}")}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = People.delete_person(socket.assigns.person)

    redirect_to =
      if socket.assigns.from_family do
        ~p"/org/#{socket.assigns.organization.id}/families/#{socket.assigns.from_family.id}"
      else
        ~p"/org/#{socket.assigns.organization.id}"
      end

    {:noreply, push_navigate(socket, to: redirect_to)}
  end

  # --- Relationship adding (delegated to shared component) ---

  def handle_event("add_relationship", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, type)
     |> update(:add_rel_key, &(&1 + 1))}
  end

  def handle_event("add_child_for_partner", %{"partner-id" => partner_id}, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, "child")
     |> assign(:adding_partner_id, String.to_integer(partner_id))
     |> update(:add_rel_key, &(&1 + 1))}
  end

  def handle_event("cancel_add_relationship", _, socket) do
    {:noreply,
     socket
     |> assign(:adding_relationship, nil)
     |> assign(:adding_partner_id, nil)}
  end

  def handle_event("edit_relationship", %{"id" => rel_id}, socket) do
    rel = Ancestry.Repo.get!(Ancestry.Relationships.Relationship, rel_id)

    form_data =
      case rel.type do
        "parent" ->
          %{
            "role" => rel.metadata && rel.metadata.role
          }

        type when type in ~w(married relationship divorced separated) ->
          base =
            if rel.metadata do
              rel.metadata |> Map.from_struct() |> Map.new(fn {k, v} -> {to_string(k), v} end)
            else
              %{}
            end

          Map.put(base, "partner_subtype", rel.type)
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

    result =
      if Ancestry.Relationships.Relationship.partner_type?(rel.type) do
        new_type = Map.get(metadata_params, "partner_subtype", rel.type)
        metadata = metadata_params |> Map.delete("partner_subtype") |> atomize_metadata()

        if new_type != rel.type do
          Relationships.update_partner_type(rel, new_type, metadata)
        else
          attrs = %{metadata: Map.put(metadata, :__type__, rel.type)}
          Relationships.update_relationship(rel, attrs)
        end
      else
        attrs = %{metadata: Map.put(atomize_metadata(metadata_params), :__type__, rel.type)}
        Relationships.update_relationship(rel, attrs)
      end

    case result do
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

  def handle_event("validate_edit_relationship", %{"metadata" => metadata_params}, socket) do
    {:noreply, assign(socket, :edit_relationship_form, to_form(metadata_params, as: :metadata))}
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

  # --- Photo gallery events ---

  def handle_event("photo_clicked", %{"id" => id}, socket) do
    {:noreply, PhotoInteractions.open_photo(socket, id)}
  end

  def handle_event("close_lightbox", _, socket) do
    {:noreply, PhotoInteractions.close_lightbox(socket)}
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, PhotoInteractions.close_lightbox(socket)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :next, fn ->
       Galleries.list_photos_for_person(socket.assigns.person.id)
     end)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :prev, fn ->
       Galleries.list_photos_for_person(socket.assigns.person.id)
     end)}
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

  def handle_event("lightbox_select", %{"id" => id}, socket) do
    {:noreply, PhotoInteractions.select_photo(socket, String.to_integer(id))}
  end

  def handle_event("toggle_panel", _, socket) do
    {:noreply, PhotoInteractions.toggle_panel(socket)}
  end

  def handle_event("tag_person", %{"person_id" => person_id, "x" => x, "y" => y}, socket) do
    {:noreply, PhotoInteractions.tag_person(socket, person_id, x, y)}
  end

  def handle_event("untag_person", %{"photo-id" => photo_id, "person-id" => person_id}, socket) do
    {:noreply, PhotoInteractions.untag_person(socket, photo_id, person_id)}
  end

  def handle_event("highlight_person_on_photo", %{"id" => dom_id}, socket) do
    {:noreply, PhotoInteractions.highlight_person(socket, dom_id)}
  end

  def handle_event("unhighlight_person_on_photo", %{"id" => dom_id}, socket) do
    {:noreply, PhotoInteractions.unhighlight_person(socket, dom_id)}
  end

  def handle_event("search_people_for_tag", %{"query" => query}, socket) do
    {payload, socket} = PhotoInteractions.search_people_for_tag(socket, query)
    {:reply, payload, socket}
  end

  @impl true
  def handle_info({:person_photo_processed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  def handle_info({:person_photo_failed, person}, socket) do
    {:noreply, assign(socket, :person, person)}
  end

  def handle_info({:comment_created, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_updated, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_deleted, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:relationship_saved, _type, _person}, socket) do
    {:noreply,
     socket
     |> load_relationships(socket.assigns.person)
     |> assign(:adding_relationship, nil)
     |> assign(:adding_partner_id, nil)
     |> put_flash(:info, "Relationship added")}
  end

  def handle_info({:relationship_error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # --- Private helpers ---

  defp load_person_photos(socket, person) do
    photos = Galleries.list_photos_for_person(person.id)

    socket
    |> assign(:person_photos, photos)
    |> assign(:person_photos_count, length(photos))
    |> stream(:person_photos, photos, reset: true)
  end

  defp load_relationships(socket, person) do
    partners = Relationships.get_active_partners(person.id)
    ex_partners = Relationships.get_former_partners(person.id)
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
          Relationships.get_partner_relationship(p1.id, p2.id)

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
    |> assign(:adding_partner_id, nil)
    |> assign_new(:add_rel_key, fn -> 0 end)
    |> assign(:editing_relationship, nil)
    |> assign(:edit_relationship_form, nil)
  end

  defp person_path(person, from_family, org) do
    if from_family do
      ~p"/org/#{org.id}/people/#{person.id}?from_family=#{from_family.id}"
    else
      ~p"/org/#{org.id}/people/#{person.id}"
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

  defp format_marriage_info(%Ancestry.Relationships.Metadata.RelationshipMetadata{}), do: nil

  defp format_marriage_info(metadata) do
    date =
      format_partial_date(
        Map.get(metadata, :marriage_day),
        Map.get(metadata, :marriage_month),
        Map.get(metadata, :marriage_year)
      )

    location = Map.get(metadata, :marriage_location)

    parts =
      [date, location]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    if parts == [], do: nil, else: Enum.join(parts, " - ")
  end

  defp partner_section_title(rel, partner) do
    cond do
      Ancestry.Relationships.Relationship.former_partner_type?(rel.type) -> "Ex-partner"
      partner.deceased -> "Late partner"
      true -> "Partner"
    end
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

  defp enter_edit_mode(socket) do
    person = socket.assigns.person

    extra_fields_present? =
      birth_name_differs?(person.given_name_at_birth, person.given_name) ||
        birth_name_differs?(person.surname_at_birth, person.surname) ||
        has_value?(person.nickname) ||
        has_value?(person.title) ||
        has_value?(person.suffix) ||
        (person.alternate_names != nil and person.alternate_names != [])

    socket
    |> assign(:editing, true)
    |> assign(:form, to_form(People.change_person(person)))
    |> assign(:show_details, extra_fields_present?)
  end

  defp maybe_enter_edit_mode(socket, true), do: enter_edit_mode(socket)
  defp maybe_enter_edit_mode(socket, false), do: socket

  defp has_value?(nil), do: false
  defp has_value?(""), do: false
  defp has_value?(_), do: true

  defp birth_name_differs?(nil, _current), do: false
  defp birth_name_differs?("", _current), do: false
  defp birth_name_differs?(birth, current), do: birth != current

  defp invert_living_to_deceased(params) do
    case Map.pop(params, "living") do
      {nil, params} -> params
      {"true", params} -> Map.put(params, "deceased", "false")
      {"false", params} -> Map.put(params, "deceased", "true")
      {_, params} -> params
    end
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} ->
        params

      {"", params} ->
        params

      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end

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
end
