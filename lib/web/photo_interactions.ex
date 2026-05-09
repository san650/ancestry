defmodule Web.PhotoInteractions do
  @moduledoc """
  Shared lightbox event handling for LiveViews that display photos.
  Both GalleryLive.Show and PersonLive.Show delegate to these functions.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Ancestry.Galleries
  alias Web.Comments.PhotoCommentsComponent

  def open_photo(socket, photo_id) do
    photo = Galleries.get_photo!(photo_id)

    socket
    |> assign(:selected_photo, photo)
    |> assign(:photo_people, Galleries.list_photo_people(photo.id))
    |> push_photo_people()
  end

  def close_lightbox(socket) do
    socket
    |> cleanup_comments_subscription()
    |> assign(:selected_photo, nil)
  end

  def navigate_lightbox(socket, direction, photos_fn) do
    current = socket.assigns.selected_photo
    photos = photos_fn.()
    idx = Enum.find_index(photos, &(&1.id == current.id)) || 0

    next_idx =
      case direction do
        :next -> min(idx + 1, length(photos) - 1)
        :prev -> max(idx - 1, 0)
      end

    new_photo = Enum.at(photos, next_idx)

    socket
    |> assign(:selected_photo, new_photo)
    |> assign(:photo_people, Galleries.list_photo_people(new_photo.id))
    |> push_photo_people()
    |> resubscribe_comments(new_photo)
  end

  def select_photo(socket, photo_id) do
    new_photo = Galleries.get_photo!(photo_id)

    socket
    |> assign(:selected_photo, new_photo)
    |> assign(:photo_people, Galleries.list_photo_people(new_photo.id))
    |> push_photo_people()
    |> resubscribe_comments(new_photo)
  end

  def toggle_panel(socket) do
    opening = not socket.assigns.panel_open

    if opening do
      topic = "photo_comments:#{socket.assigns.selected_photo.id}"

      if Phoenix.LiveView.connected?(socket) do
        Phoenix.PubSub.subscribe(Ancestry.PubSub, topic)
      end

      socket
      |> assign(:panel_open, true)
      |> assign(:comments_topic, topic)
    else
      cleanup_comments_subscription(socket)
    end
  end

  def tag_person(socket, person_id, x, y) do
    photo = socket.assigns.selected_photo

    command =
      Ancestry.Commands.TagPersonInPhoto.new!(%{
        photo_id: photo.id,
        person_id: String.to_integer(person_id),
        x: x,
        y: y
      })

    case Ancestry.Bus.dispatch(socket.assigns.current_scope, command) do
      {:ok, _} ->
        socket
        |> assign(:photo_people, Galleries.list_photo_people(photo.id))
        |> push_photo_people()

      _ ->
        socket
    end
  end

  def untag_person(socket, photo_id, person_id) do
    command =
      Ancestry.Commands.UntagPersonFromPhoto.new!(%{
        photo_id: String.to_integer(photo_id),
        person_id: String.to_integer(person_id)
      })

    Ancestry.Bus.dispatch(socket.assigns.current_scope, command)

    socket
    |> assign(:photo_people, Galleries.list_photo_people(socket.assigns.selected_photo.id))
    |> push_photo_people()
  end

  def search_people_for_tag(socket, query) do
    results =
      if String.length(query) >= 2 do
        Ancestry.People.search_all_people(query, socket.assigns.current_scope.organization.id)
      else
        []
      end

    payload = %{
      results:
        Enum.map(results, fn p ->
          %{
            id: p.id,
            name: Ancestry.People.Person.display_name(p),
            has_photo: p.photo != nil && p.photo_status == "processed",
            photo_url:
              if(p.photo && p.photo_status == "processed",
                do: Ancestry.Uploaders.PersonPhoto.url({p.photo, p}, :thumbnail),
                else: nil
              )
          }
        end)
    }

    {payload, socket}
  end

  def highlight_person(socket, dom_id) do
    pp_id = dom_id |> String.replace("photo-person-", "") |> String.to_integer()
    pp = Enum.find(socket.assigns.photo_people, &(&1.id == pp_id))

    if pp do
      push_event(socket, "highlight_person", %{person_id: pp.person_id})
    else
      socket
    end
  end

  def unhighlight_person(socket, dom_id) do
    pp_id = dom_id |> String.replace("photo-person-", "") |> String.to_integer()
    pp = Enum.find(socket.assigns.photo_people, &(&1.id == pp_id))

    if pp do
      push_event(socket, "unhighlight_person", %{person_id: pp.person_id})
    else
      socket
    end
  end

  def handle_comment_info(socket, {:comment_created, comment}) do
    send_update(PhotoCommentsComponent, id: "photo-comments", comment_created: comment)
    {:noreply, socket}
  end

  def handle_comment_info(socket, {:comment_updated, comment}) do
    send_update(PhotoCommentsComponent, id: "photo-comments", comment_updated: comment)
    {:noreply, socket}
  end

  def handle_comment_info(socket, {:comment_deleted, comment}) do
    send_update(PhotoCommentsComponent, id: "photo-comments", comment_deleted: comment)
    {:noreply, socket}
  end

  def start_link_person(socket) do
    assign(socket, linking_person: true, link_search_query: "", link_search_results: [])
  end

  def cancel_link_person(socket) do
    assign(socket, linking_person: false, link_search_query: "", link_search_results: [])
  end

  def search_link_person(socket, query) do
    results =
      if String.length(query) >= 2 do
        tagged_ids = Enum.map(socket.assigns.photo_people, & &1.person_id)

        Ancestry.People.search_all_people(query, socket.assigns.current_scope.organization.id)
        |> Enum.reject(fn p -> p.id in tagged_ids end)
      else
        []
      end

    assign(socket, link_search_query: query, link_search_results: results)
  end

  def link_existing_person(socket, person_id) do
    photo = socket.assigns.selected_photo

    command =
      Ancestry.Commands.TagPersonInPhoto.new!(%{
        photo_id: photo.id,
        person_id: String.to_integer(person_id),
        x: nil,
        y: nil
      })

    Ancestry.Bus.dispatch(socket.assigns.current_scope, command)

    socket
    |> assign(:photo_people, Galleries.list_photo_people(photo.id))
    |> cancel_link_person()
    |> push_photo_people()
  end

  def push_photo_people(socket) do
    people_data =
      Enum.map(socket.assigns.photo_people, fn pp ->
        %{
          person_id: pp.person_id,
          x: pp.x,
          y: pp.y,
          person_name: Ancestry.People.Person.display_name(pp.person)
        }
      end)

    push_event(socket, "photo_people_updated", %{people: people_data})
  end

  defp cleanup_comments_subscription(socket) do
    if socket.assigns.comments_topic && Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.unsubscribe(Ancestry.PubSub, socket.assigns.comments_topic)
    end

    socket
    |> assign(:panel_open, false)
    |> assign(:comments_topic, nil)
  end

  defp resubscribe_comments(socket, new_photo) do
    if socket.assigns.panel_open and Phoenix.LiveView.connected?(socket) do
      old_topic = socket.assigns.comments_topic
      new_topic = "photo_comments:#{new_photo.id}"

      if old_topic && old_topic != new_topic do
        Phoenix.PubSub.unsubscribe(Ancestry.PubSub, old_topic)
      end

      if old_topic != new_topic do
        Phoenix.PubSub.subscribe(Ancestry.PubSub, new_topic)
      end

      assign(socket, :comments_topic, new_topic)
    else
      socket
    end
  end
end
