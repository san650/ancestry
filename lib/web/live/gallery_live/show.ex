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
     |> assign(:upload_modal, nil)
     |> assign(:upload_queue, [])
     |> assign(:upload_cancel_confirm, false)
     |> stream(:photos, Galleries.list_photos(id))
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif),
       max_entries: 10,
       max_file_size: 300 * 1_048_576,
       auto_upload: true
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("queue_files", %{"files" => files}, socket) do
    upload_queue =
      Enum.map(files, fn %{"name" => name, "size" => size} ->
        %{name: name, size: size, status: :pending, error: nil}
      end)

    {:noreply,
     socket
     |> assign(:upload_modal, :uploading)
     |> assign(:upload_queue, upload_queue)
     |> assign(:upload_cancel_confirm, false)}
  end

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

    {uploaded, errored} =
      consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = ext_from_content_type(entry.client_type)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)

        case Galleries.create_photo(%{
               gallery_id: gallery.id,
               original_path: dest_path,
               original_filename: entry.client_name,
               content_type: entry.client_type
             }) do
          {:ok, photo} -> {:ok, {:ok, photo}}
          {:error, _} -> {:ok, {:error, entry.client_name}}
        end
      end)
      |> Enum.split_with(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    uploaded_photos = Enum.map(uploaded, fn {:ok, photo} -> photo end)
    errored_names = Enum.map(errored, fn {:error, name} -> name end)

    upload_queue =
      Enum.map(socket.assigns.upload_queue, fn file ->
        cond do
          Enum.any?(uploaded_photos, &(&1.original_filename == file.name)) ->
            %{file | status: :done}

          file.name in errored_names ->
            %{file | status: :error, error: "Upload failed"}

          true ->
            file
        end
      end)

    all_done? = Enum.all?(upload_queue, &(&1.status in [:done, :error]))
    upload_modal = if all_done?, do: :done, else: :uploading

    socket =
      socket
      |> assign(:upload_queue, upload_queue)
      |> assign(:upload_modal, upload_modal)
      |> push_event("batch_complete", %{})

    socket = Enum.reduce(uploaded_photos, socket, &stream_insert(&2, :photos, &1))
    {:noreply, socket}
  end

  def handle_event("close_upload_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:upload_modal, nil)
     |> assign(:upload_queue, [])
     |> assign(:upload_cancel_confirm, false)}
  end

  def handle_event("cancel_upload_modal", _, socket) do
    pending_count =
      Enum.count(socket.assigns.upload_queue, &(&1.status == :pending))

    if pending_count > 0 do
      {:noreply, assign(socket, :upload_cancel_confirm, true)}
    else
      {:noreply,
       socket
       |> assign(:upload_modal, nil)
       |> assign(:upload_queue, [])
       |> assign(:upload_cancel_confirm, false)}
    end
  end

  def handle_event("confirm_cancel_upload", _, socket) do
    {:noreply,
     socket
     |> assign(:upload_modal, nil)
     |> assign(:upload_queue, [])
     |> assign(:upload_cancel_confirm, false)
     |> push_event("reset_queue", %{})}
  end

  def handle_event("dismiss_cancel_confirm", _, socket) do
    {:noreply, assign(socket, :upload_cancel_confirm, false)}
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
    {:noreply, assign(socket, :selected_photo, Galleries.get_photo!(id))}
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
