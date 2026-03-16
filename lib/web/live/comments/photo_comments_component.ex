defmodule Web.Comments.PhotoCommentsComponent do
  use Web, :live_component

  alias Ancestry.Comments
  alias Ancestry.Comments.PhotoComment

  @impl true
  def update(%{comment_created: comment}, socket) do
    {:ok, stream_insert(socket, :comments, comment)}
  end

  def update(%{comment_updated: comment}, socket) do
    {:ok, stream_insert(socket, :comments, comment)}
  end

  def update(%{comment_deleted: comment}, socket) do
    {:ok, stream_delete(socket, :comments, comment)}
  end

  def update(assigns, socket) do
    photo_id = assigns.photo_id
    comments = Comments.list_photo_comments(photo_id)
    changeset = Comments.change_photo_comment(%PhotoComment{})

    {:ok,
     socket
     |> assign(:photo_id, photo_id)
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_form, nil)
     |> assign(:form, to_form(changeset, as: :comment))
     |> stream(:comments, comments, reset: true)}
  end

  @impl true
  def handle_event("save_comment", %{"comment" => %{"text" => text}}, socket) do
    case Comments.create_photo_comment(%{photo_id: socket.assigns.photo_id, text: text}) do
      {:ok, _comment} ->
        changeset = Comments.change_photo_comment(%PhotoComment{})
        {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("edit_comment", %{"id" => id}, socket) do
    comment = Comments.get_photo_comment!(id)
    changeset = Comments.change_photo_comment(comment, %{text: comment.text})

    {:noreply,
     socket
     |> assign(:editing_comment_id, comment.id)
     |> assign(:edit_form, to_form(changeset, as: :comment))
     |> stream_insert(:comments, comment)}
  end

  def handle_event("save_edit", %{"comment" => comment_params}, socket) do
    comment = Comments.get_photo_comment!(socket.assigns.editing_comment_id)

    case Comments.update_photo_comment(comment, comment_params) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, nil)
         |> assign(:edit_form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_form, nil)}
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    comment = Comments.get_photo_comment!(id)
    {:ok, _} = Comments.delete_photo_comment(comment)
    {:noreply, socket}
  end

  def handle_event("close_comments", _, socket) do
    send(self(), {:close_comments})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="photo-comments-panel" class="flex flex-col h-full bg-black/80 text-white">
      <%!-- Header --%>
      <div class="flex items-center justify-between px-4 py-3 border-b border-white/10 shrink-0">
        <h3 class="text-sm font-semibold text-white/90 tracking-wide">Comments</h3>
        <button
          id="close-comments-btn"
          phx-click="close_comments"
          phx-target={@myself}
          class="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/10 transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>

      <%!-- Scrollable comment list --%>
      <div class="flex-1 overflow-y-auto min-h-0 px-4 py-3">
        <div id="comments-list" phx-update="stream" class="space-y-3">
          <div id="comments-empty" class="hidden only:block text-center py-10">
            <.icon name="hero-chat-bubble-left-right" class="w-8 h-8 text-white/15 mx-auto mb-2" />
            <p class="text-sm text-white/30">No comments yet</p>
          </div>

          <div
            :for={{id, comment} <- @streams.comments}
            id={id}
            class="group relative rounded-lg px-3 py-2.5 hover:bg-white/5 transition-colors"
          >
            <%= if @editing_comment_id == comment.id do %>
              <.form
                for={@edit_form}
                id={"edit-comment-#{comment.id}"}
                phx-submit="save_edit"
                phx-target={@myself}
                class="space-y-2"
              >
                <textarea
                  name="comment[text]"
                  id={"edit-comment-text-#{comment.id}"}
                  rows="2"
                  class="w-full bg-white/10 border border-white/20 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:outline-none focus:border-white/40 focus:ring-1 focus:ring-white/20 resize-none"
                  phx-mounted={JS.dispatch("focus", to: "#edit-comment-text-#{comment.id}")}
                >{Phoenix.HTML.Form.normalize_value("textarea", Ecto.Changeset.get_field(@edit_form.source, :text))}</textarea>
                <div class="flex items-center gap-2">
                  <button
                    type="submit"
                    class="px-3 py-1 bg-primary hover:bg-primary/80 text-white text-xs font-medium rounded-md transition-colors"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    phx-target={@myself}
                    class="px-3 py-1 bg-white/10 hover:bg-white/20 text-white/70 text-xs font-medium rounded-md transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            <% else %>
              <p class="text-sm text-white/80 leading-relaxed whitespace-pre-wrap break-words">
                {comment.text}
              </p>
              <div class="flex items-center justify-between mt-1.5">
                <time class="text-xs text-white/30">{format_relative_time(comment.inserted_at)}</time>
                <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    phx-click="edit_comment"
                    phx-value-id={comment.id}
                    phx-target={@myself}
                    class="p-1 rounded text-white/30 hover:text-white hover:bg-white/10 transition-colors"
                    title="Edit comment"
                  >
                    <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                  </button>
                  <button
                    phx-click="delete_comment"
                    phx-value-id={comment.id}
                    phx-target={@myself}
                    data-confirm="Delete this comment?"
                    class="p-1 rounded text-white/30 hover:text-red-400 hover:bg-white/10 transition-colors"
                    title="Delete comment"
                  >
                    <.icon name="hero-trash" class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- New comment form --%>
      <div class="shrink-0 border-t border-white/10 px-4 py-3">
        <.form
          for={@form}
          id="new-comment-form"
          phx-submit="save_comment"
          phx-target={@myself}
          class="flex items-end gap-2"
        >
          <div class="flex-1">
            <textarea
              name="comment[text]"
              id="new-comment-text"
              rows="1"
              placeholder="Add a comment..."
              class="w-full bg-white/10 border border-white/15 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:outline-none focus:border-white/30 focus:ring-1 focus:ring-white/15 resize-none"
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
          </div>
          <button
            type="submit"
            class="p-2 bg-primary hover:bg-primary/80 text-white rounded-lg transition-colors shrink-0"
            title="Post comment"
          >
            <.icon name="hero-paper-airplane" class="w-4 h-4" />
          </button>
        </.form>
      </div>
    </div>
    """
  end

  defp format_relative_time(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
