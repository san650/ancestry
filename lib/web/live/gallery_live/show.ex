defmodule Web.GalleryLive.Show do
  use Web, :live_view

  alias Ancestry.Galleries
  alias Web.PhotoInteractions

  @impl true
  def mount(%{"family_id" => family_id, "id" => id}, _session, socket) do
    family = Ancestry.Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    gallery = Galleries.get_gallery!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "gallery:#{id}")
    end

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:gallery, gallery)
     |> assign(:grid_layout, :masonry)
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_photos, false)
     |> assign(:selected_photo, nil)
     |> assign(:panel_open, false)
     |> assign(:photo_people, [])
     |> assign(:comments_topic, nil)
     |> assign(:show_upload_modal, false)
     |> assign(:upload_results, [])
     |> assign(:show_quick_person_modal, false)
     |> assign(:pending_tag, nil)
     |> assign(:quick_person_prefill, nil)
     |> assign(:linking_person, false)
     |> assign(:link_search_query, "")
     |> assign(:link_search_results, [])
     |> assign(:gallery_photos, Galleries.list_photos(id))
     |> stream(:photos, Galleries.list_photos(id))
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif),
       max_entries: 50,
       max_file_size: 300 * 1_048_576,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp handle_progress(:photos, _entry, socket) do
    entries = socket.assigns.uploads.photos.entries
    all_done? = entries != [] and Enum.all?(entries, & &1.done?)

    socket =
      if not socket.assigns.show_upload_modal and entries != [] do
        assign(socket, :show_upload_modal, true)
      else
        socket
      end

    if all_done? do
      process_uploads(socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_layout", _, socket) do
    new_layout = if socket.assigns.grid_layout == :masonry, do: :uniform, else: :masonry
    {:noreply, assign(socket, :grid_layout, new_layout)}
  end

  def handle_event("toggle_select_mode", _, socket) do
    {:noreply,
     socket
     |> assign(:selection_mode, !socket.assigns.selection_mode)
     |> assign(:selected_ids, MapSet.new())
     |> stream(:photos, Galleries.list_photos(socket.assigns.gallery.id), reset: true)}
  end

  def handle_event("toggle_photo_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    photo = Galleries.get_photo!(id)

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> stream_insert(:photos, photo)}
  end

  def handle_event("upload_photos", _params, socket) do
    process_uploads(socket)
  end

  def handle_event("close_upload_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_upload_modal, false)
     |> assign(:upload_results, [])}
  end

  def handle_event("request_delete_photos", _, socket) do
    {:noreply, assign(socket, :confirm_delete_photos, true)}
  end

  def handle_event("cancel_delete_photos", _, socket) do
    {:noreply, assign(socket, :confirm_delete_photos, false)}
  end

  def handle_event("confirm_delete_photos", _, socket) do
    scope = socket.assigns.current_scope

    socket =
      Enum.reduce(MapSet.to_list(socket.assigns.selected_ids), socket, fn id, acc ->
        command = Ancestry.Commands.RemovePhotoFromGallery.new!(%{photo_id: id})

        case Ancestry.Bus.dispatch(scope, command) do
          {:ok, photo} -> stream_delete(acc, :photos, photo)
          _ -> acc
        end
      end)

    {:noreply,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_photos, false)
     |> assign(:gallery_photos, Galleries.list_photos(socket.assigns.gallery.id))
     |> stream(:photos, Galleries.list_photos(socket.assigns.gallery.id), reset: true)}
  end

  def handle_event("photo_clicked", %{"id" => id}, socket) do
    if socket.assigns.selection_mode do
      handle_event("toggle_photo_select", %{"id" => to_string(id)}, socket)
    else
      {:noreply, PhotoInteractions.open_photo(socket, id)}
    end
  end

  def handle_event("toggle_panel", _, socket) do
    {:noreply, PhotoInteractions.toggle_panel(socket)}
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
       Galleries.list_photos(socket.assigns.gallery.id)
     end)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :prev, fn ->
       Galleries.list_photos(socket.assigns.gallery.id)
     end)}
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

  def handle_event("lightbox_select", %{"id" => id}, socket) do
    {:noreply, PhotoInteractions.select_photo(socket, String.to_integer(id))}
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

  def handle_event(
        "create_person_from_tag",
        %{"x" => x, "y" => y, "query" => query, "photo_id" => photo_id},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:pending_tag, %{x: x, y: y, photo_id: String.to_integer(photo_id)})
     |> assign(:show_quick_person_modal, true)
     |> assign(:quick_person_prefill, query)}
  end

  def handle_event("start_link_person", _, socket) do
    {:noreply, PhotoInteractions.start_link_person(socket)}
  end

  def handle_event("cancel_link_person", _, socket) do
    {:noreply, PhotoInteractions.cancel_link_person(socket)}
  end

  def handle_event("link_person_search", %{"value" => query}, socket) do
    {:noreply, PhotoInteractions.search_link_person(socket, query)}
  end

  def handle_event("link_existing_person", %{"person-id" => person_id}, socket) do
    {:noreply, PhotoInteractions.link_existing_person(socket, person_id)}
  end

  def handle_event("create_person_from_link", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:pending_tag, %{x: nil, y: nil, photo_id: socket.assigns.selected_photo.id})
     |> assign(:show_quick_person_modal, true)
     |> assign(:quick_person_prefill, query)
     |> PhotoInteractions.cancel_link_person()}
  end

  @impl true
  def handle_info({:photo_processed, photo}, socket) do
    {:noreply,
     socket
     |> assign(:gallery_photos, Galleries.list_photos(socket.assigns.gallery.id))
     |> stream_insert(:photos, photo)}
  end

  def handle_info({:photo_failed, photo}, socket) do
    {:noreply, stream_insert(socket, :photos, photo)}
  end

  def handle_info({:comment_created, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_updated, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_deleted, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:person_created, person}, socket) do
    socket =
      case socket.assigns[:pending_tag] do
        %{x: x, y: y, photo_id: photo_id} ->
          Galleries.tag_person_in_photo(photo_id, person.id, x, y)

          if socket.assigns.selected_photo && socket.assigns.selected_photo.id == photo_id do
            socket
            |> assign(:photo_people, Galleries.list_photo_people(photo_id))
            |> PhotoInteractions.push_photo_people()
          else
            socket
          end

        nil ->
          socket
      end

    {:noreply,
     socket
     |> assign(:pending_tag, nil)
     |> assign(:show_quick_person_modal, false)
     |> assign(:quick_person_prefill, nil)}
  end

  def handle_info({:quick_person_cancelled}, socket) do
    {:noreply,
     socket
     |> assign(:pending_tag, nil)
     |> assign(:show_quick_person_modal, false)
     |> assign(:quick_person_prefill, nil)}
  end

  # LiveView traps exits; upload writer tasks send :EXIT on completion
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  # Catch-all for unexpected messages (e.g. :query_fired from Tidewave MCP)
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp process_uploads(socket) do
    gallery = socket.assigns.gallery

    results =
      consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
        contents = File.read!(tmp_path)

        file_hash =
          :crypto.hash(:sha256, contents)
          |> Base.encode16(case: :lower)

        if Galleries.photo_exists_in_gallery?(gallery.id, file_hash) do
          {:ok, {:duplicate, entry.client_name}}
        else
          uuid = Ecto.UUID.generate()
          ext = ext_from_content_type(entry.client_type)
          dest_key = Path.join(["uploads", "originals", uuid, "photo#{ext}"])
          original_path = Ancestry.Storage.store_original_bytes(contents, dest_key)

          attrs = %{
            gallery_id: gallery.id,
            original_path: original_path,
            original_filename: entry.client_name,
            content_type: entry.client_type,
            file_hash: file_hash
          }

          case Ancestry.Bus.dispatch(
                 socket.assigns.current_scope,
                 Ancestry.Commands.AddPhotoToGallery.new!(attrs)
               ) do
            {:ok, photo} -> {:ok, {:ok, photo}}
            {:error, _, _} -> {:ok, {:error, entry.client_name}}
            {:error, _} -> {:ok, {:error, entry.client_name}}
          end
        end
      end)

    {uploaded, errored} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:duplicate, _} -> true
        {:error, _} -> false
      end)

    uploaded_photos =
      Enum.flat_map(uploaded, fn
        {:ok, photo} -> [photo]
        {:duplicate, _} -> []
      end)

    upload_results =
      Enum.map(uploaded, fn
        {:ok, photo} -> %{name: photo.original_filename, status: :ok}
        {:duplicate, name} -> %{name: name, status: :ok}
      end) ++
        Enum.map(errored, fn {:error, name} ->
          %{name: name, status: :error, error: "Upload failed"}
        end)

    socket =
      socket
      |> assign(:upload_results, upload_results)
      |> assign(:show_upload_modal, true)

    socket = Enum.reduce(uploaded_photos, socket, &stream_insert(&2, :photos, &1))
    {:noreply, socket}
  end

  defp ext_from_content_type("image/jpeg"), do: ".jpg"
  defp ext_from_content_type("image/jpg"), do: ".jpg"
  defp ext_from_content_type("image/png"), do: ".png"
  defp ext_from_content_type("image/webp"), do: ".webp"
  defp ext_from_content_type("image/gif"), do: ".gif"
  defp ext_from_content_type("image/x-adobe-dng"), do: ".dng"
  defp ext_from_content_type("image/x-nikon-nef"), do: ".nef"
  defp ext_from_content_type("image/tiff"), do: ".tiff"
  defp ext_from_content_type(_), do: ".jpg"

  defp upload_error_to_string(:too_large), do: gettext("File too large (max 300MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("File type not supported")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files (max 50)")
  defp upload_error_to_string(err), do: gettext("Upload error: %{error}", error: inspect(err))
end
