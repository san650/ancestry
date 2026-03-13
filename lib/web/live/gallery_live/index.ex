defmodule Web.GalleryLive.Index do
  use Web, :live_view

  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_new_modal, false)
     |> assign(:confirm_delete_gallery, nil)
     |> assign(:form, to_form(Galleries.change_gallery(%Gallery{})))
     |> stream(:galleries, Galleries.list_galleries())}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_new_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_modal, true)
     |> assign(:form, to_form(Galleries.change_gallery(%Gallery{})))}
  end

  def handle_event("close_new_modal", _, socket) do
    {:noreply, assign(socket, :show_new_modal, false)}
  end

  def handle_event("validate_gallery", %{"gallery" => params}, socket) do
    changeset =
      %Gallery{}
      |> Galleries.change_gallery(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save_gallery", %{"gallery" => params}, socket) do
    case Galleries.create_gallery(params) do
      {:ok, gallery} ->
        {:noreply,
         socket
         |> assign(:show_new_modal, false)
         |> stream_insert(:galleries, gallery)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_gallery, Galleries.get_gallery!(id))}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete_gallery, nil)}
  end

  def handle_event("confirm_delete", _, socket) do
    gallery = socket.assigns.confirm_delete_gallery
    {:ok, _} = Galleries.delete_gallery(gallery)

    {:noreply,
     socket
     |> assign(:confirm_delete_gallery, nil)
     |> stream_delete(:galleries, gallery)}
  end
end
