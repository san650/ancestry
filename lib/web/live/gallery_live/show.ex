defmodule Web.GalleryLive.Show do
  use Web, :live_view

  alias Family.Galleries

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    gallery = Galleries.get_gallery!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Family.PubSub, "gallery:#{id}")
    end

    {:ok,
     socket
     |> assign(:gallery, gallery)
     |> assign(:grid_layout, :masonry)
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_photos, false)
     |> assign(:selected_photo, nil)
     |> stream(:photos, Galleries.list_photos(id))
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif),
       max_entries: 10,
       max_file_size: 300 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

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
     |> assign(:selected_ids, MapSet.new())}
  end

  def handle_event("toggle_photo_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("upload_photos", _params, socket) do
    gallery = socket.assigns.gallery

    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = ext_from_content_type(entry.client_type)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)

        {:ok, photo} =
          Galleries.create_photo(%{
            gallery_id: gallery.id,
            original_path: dest_path,
            original_filename: entry.client_name,
            content_type: entry.client_type
          })

        Oban.insert!(Family.Workers.ProcessPhotoJob.new(%{photo_id: photo.id}))
        {:ok, photo}
      end)

    socket = Enum.reduce(uploaded, socket, &stream_insert(&2, :photos, &1))
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("request_delete_photos", _, socket) do
    {:noreply, assign(socket, :confirm_delete_photos, true)}
  end

  def handle_event("cancel_delete_photos", _, socket) do
    {:noreply, assign(socket, :confirm_delete_photos, false)}
  end

  def handle_event("confirm_delete_photos", _, socket) do
    socket =
      Enum.reduce(MapSet.to_list(socket.assigns.selected_ids), socket, fn id, acc ->
        photo = Galleries.get_photo!(id)
        {:ok, _} = Galleries.delete_photo(photo)
        stream_delete(acc, :photos, photo)
      end)

    {:noreply,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_photos, false)}
  end

  def handle_event("open_lightbox", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_photo, Galleries.get_photo!(String.to_integer(id)))}
  end

  def handle_event("close_lightbox", _, socket) do
    {:noreply, assign(socket, :selected_photo, nil)}
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :selected_photo, nil)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply, navigate_lightbox(socket, :next)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply, navigate_lightbox(socket, :prev)}
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

  def handle_event("lightbox_select", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_photo, Galleries.get_photo!(String.to_integer(id)))}
  end

  @impl true
  def handle_info({:photo_processed, photo}, socket) do
    {:noreply, stream_insert(socket, :photos, photo)}
  end

  def handle_info({:photo_failed, photo}, socket) do
    {:noreply, stream_insert(socket, :photos, photo)}
  end

  defp navigate_lightbox(socket, direction) do
    current = socket.assigns.selected_photo
    photos = Galleries.list_photos(socket.assigns.gallery.id)
    idx = Enum.find_index(photos, &(&1.id == current.id)) || 0

    next_idx =
      case direction do
        :next -> min(idx + 1, length(photos) - 1)
        :prev -> max(idx - 1, 0)
      end

    assign(socket, :selected_photo, Enum.at(photos, next_idx))
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

  defp upload_error_to_string(:too_large), do: "File too large (max 300MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 10)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
