defmodule Web.MemoryLive.Form do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Memories
  alias Ancestry.Memories.Memory
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id, "vault_id" => vault_id} = params, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    vault = Memories.get_vault!(vault_id)

    if vault.family_id != family.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Memories.Vault
    end

    galleries = Galleries.list_galleries(family_id)
    {memory, form} = load_memory(params)
    cover_photo = if memory, do: memory.cover_photo, else: nil

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:vault, vault)
     |> assign(:galleries, galleries)
     |> assign(:memory, memory)
     |> assign(:form, form)
     |> assign(:cover_photo, cover_photo)
     |> assign(:show_photo_picker, false)
     |> assign(:picker_mode, nil)
     |> assign(:picker_gallery, nil)
     |> assign(:picker_photos, [])
     |> assign(:confirm_delete, false)
     |> assign(:show_quick_person_modal, false)
     |> assign(:quick_person_prefill, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # --- Form events ---

  @impl true
  def handle_event("validate", %{"memory" => params}, socket) do
    changeset =
      (socket.assigns.memory || %Memory{})
      |> Memories.change_memory(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"memory" => params}, socket) do
    params = maybe_put_cover_photo_id(params, socket.assigns.cover_photo)

    case socket.assigns.live_action do
      :new -> save_new(socket, params)
      :edit -> save_edit(socket, params)
    end
  end

  # --- Photo picker events ---

  def handle_event("open_cover_picker", _, socket) do
    {:noreply,
     socket
     |> assign(:show_photo_picker, true)
     |> assign(:picker_mode, :cover)
     |> assign(:picker_gallery, nil)
     |> assign(:picker_photos, [])}
  end

  def handle_event("open_content_picker", _, socket) do
    {:noreply,
     socket
     |> assign(:show_photo_picker, true)
     |> assign(:picker_mode, :content)
     |> assign(:picker_gallery, nil)
     |> assign(:picker_photos, [])}
  end

  def handle_event("close_photo_picker", _, socket) do
    {:noreply,
     socket
     |> assign(:show_photo_picker, false)
     |> assign(:picker_mode, nil)
     |> assign(:picker_gallery, nil)
     |> assign(:picker_photos, [])}
  end

  def handle_event("select_picker_gallery", %{"id" => gallery_id}, socket) do
    gallery = Galleries.get_gallery!(gallery_id)

    photos =
      Galleries.list_photos(gallery_id)
      |> Enum.filter(&(&1.status == "processed"))

    {:noreply,
     socket
     |> assign(:picker_gallery, gallery)
     |> assign(:picker_photos, photos)}
  end

  def handle_event("picker_back_to_galleries", _, socket) do
    {:noreply,
     socket
     |> assign(:picker_gallery, nil)
     |> assign(:picker_photos, [])}
  end

  def handle_event("select_photo", %{"id" => photo_id}, socket) do
    photo = Galleries.get_photo!(photo_id)

    case socket.assigns.picker_mode do
      :cover ->
        {:noreply,
         socket
         |> assign(:cover_photo, photo)
         |> assign(:show_photo_picker, false)
         |> assign(:picker_mode, nil)
         |> assign(:picker_gallery, nil)
         |> assign(:picker_photos, [])}

      :content ->
        url = Ancestry.Uploaders.Photo.url({photo.image, photo}, :large)

        {:noreply,
         socket
         |> push_event("insert_photo", %{url: url, photo_id: photo.id})
         |> assign(:show_photo_picker, false)
         |> assign(:picker_mode, nil)
         |> assign(:picker_gallery, nil)
         |> assign(:picker_photos, [])}
    end
  end

  def handle_event("remove_cover_photo", _, socket) do
    {:noreply, assign(socket, :cover_photo, nil)}
  end

  # --- Delete events ---

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = Memories.delete_memory(socket.assigns.memory)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Memory deleted"))
     |> push_navigate(to: vault_path(socket))}
  end

  # --- Mention search ---

  def handle_event("search_mentions", %{"query" => query}, socket) do
    org_id = socket.assigns.current_scope.organization.id

    results =
      People.search_all_people(query, org_id)
      |> Enum.map(fn person ->
        %{
          id: person.id,
          name: Ancestry.People.Person.display_name(person)
        }
      end)

    {:noreply, push_event(socket, "mention_results", %{results: results})}
  end

  # --- Create person from mention ---

  def handle_event("create_person_from_mention", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:show_quick_person_modal, true)
     |> assign(:quick_person_prefill, query)}
  end

  # --- handle_info callbacks ---

  @impl true
  def handle_info({:person_created, person}, socket) do
    display_name = Ancestry.People.Person.display_name(person)

    # Push mention data to JS so Trix hook can insert the attachment.
    # The MemoryMention record is created automatically by ContentParser
    # when the memory form is saved — no need to create it here.
    # Push unconditionally — the JS handler guards against null saved state.
    {:noreply,
     socket
     |> push_event("mention_created", %{id: person.id, name: display_name})
     |> assign(:show_quick_person_modal, false)
     |> assign(:quick_person_prefill, nil)}
  end

  def handle_info({:quick_person_cancelled}, socket) do
    {:noreply,
     socket
     |> assign(:show_quick_person_modal, false)
     |> assign(:quick_person_prefill, nil)
     |> push_event("mention_cancelled", %{})}
  end

  # --- Private ---

  defp load_memory(%{"memory_id" => memory_id}) do
    memory = Memories.get_memory!(memory_id)
    form = to_form(Memories.change_memory(memory, %{}))
    {memory, form}
  end

  defp load_memory(_params) do
    form = to_form(Memories.change_memory(%Memory{}, %{}))
    {nil, form}
  end

  defp save_new(socket, params) do
    vault = socket.assigns.vault
    account = socket.assigns.current_scope.account

    case Memories.create_memory(vault, account, params) do
      {:ok, _memory} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Memory created"))
         |> push_navigate(to: redirect_path(socket))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_edit(socket, params) do
    memory = socket.assigns.memory

    case Memories.update_memory(memory, params) do
      {:ok, _memory} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Memory updated"))
         |> push_navigate(to: redirect_path(socket))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp maybe_put_cover_photo_id(params, nil), do: Map.put(params, "cover_photo_id", nil)
  defp maybe_put_cover_photo_id(params, photo), do: Map.put(params, "cover_photo_id", photo.id)

  defp redirect_path(socket) do
    org_id = socket.assigns.current_scope.organization.id
    family_id = socket.assigns.family.id
    vault_id = socket.assigns.vault.id

    case socket.assigns.live_action do
      :new ->
        ~p"/org/#{org_id}/families/#{family_id}/vaults/#{vault_id}"

      :edit ->
        memory_id = socket.assigns.memory.id
        ~p"/org/#{org_id}/families/#{family_id}/vaults/#{vault_id}/memories/#{memory_id}"
    end
  end

  defp vault_path(socket) do
    org_id = socket.assigns.current_scope.organization.id
    family_id = socket.assigns.family.id
    vault_id = socket.assigns.vault.id
    ~p"/org/#{org_id}/families/#{family_id}/vaults/#{vault_id}"
  end
end
