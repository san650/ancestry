defmodule Web.Comments.PhotoCommentsComponent do
  use Web, :live_component

  alias Ancestry.Comments
  alias Ancestry.Comments.PhotoComment

  @impl true
  def update(%{comment_created: comment}, socket) do
    {:ok,
     socket
     |> update(:stream_count_comments, &(&1 + 1))
     |> stream_insert(:comments, comment)}
  end

  def update(%{comment_updated: comment}, socket) do
    {:ok, stream_insert(socket, :comments, comment)}
  end

  def update(%{comment_deleted: comment}, socket) do
    {:ok,
     socket
     |> update(:stream_count_comments, &max(&1 - 1, 0))
     |> stream_delete(:comments, comment)}
  end

  def update(assigns, socket) do
    photo_id = assigns.photo_id
    comments = Comments.list_photo_comments(photo_id)
    changeset = Comments.change_photo_comment(%PhotoComment{})

    {:ok,
     socket
     |> assign(:photo_id, photo_id)
     |> assign(:current_scope, assigns.current_scope)
     |> assign(:editing_comment_id, nil)
     |> assign(:selected_comment_id, nil)
     |> assign(:edit_form, nil)
     |> assign(:form, to_form(changeset, as: :comment))
     |> assign(:stream_count_comments, length(comments))
     |> stream(:comments, comments, reset: true)}
  end

  @impl true
  def handle_event("save_comment", %{"comment" => %{"text" => text}}, socket) do
    attrs = %{photo_id: socket.assigns.photo_id, text: text}

    case Ancestry.Commands.CreatePhotoComment.new(attrs) do
      {:ok, command} ->
        socket.assigns.current_scope
        |> Ancestry.Bus.dispatch(command)
        |> handle_dispatch_result(socket)

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("select_comment", %{"id" => id}, socket) do
    comment = Comments.get_photo_comment!(id)
    previous_id = socket.assigns.selected_comment_id

    selected =
      if previous_id == comment.id, do: nil, else: comment.id

    socket =
      socket
      |> assign(:selected_comment_id, selected)
      |> stream_insert(:comments, comment)

    # If we just switched selection from a different comment, re-insert
    # the previously-selected comment so it re-renders in unselected state.
    socket =
      if previous_id && previous_id != comment.id do
        previous = Comments.get_photo_comment!(previous_id)
        stream_insert(socket, :comments, previous)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("edit_comment", %{"id" => id}, socket) do
    comment = Comments.get_photo_comment!(id)

    if comment.account_id == socket.assigns.current_scope.account.id do
      changeset = Comments.change_photo_comment(comment, %{text: comment.text})

      {:noreply,
       socket
       |> assign(:editing_comment_id, comment.id)
       |> assign(:selected_comment_id, nil)
       |> assign(:edit_form, to_form(changeset, as: :comment))
       |> stream_insert(:comments, comment)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_edit", %{"comment" => %{"text" => text}}, socket) do
    attrs = %{photo_comment_id: socket.assigns.editing_comment_id, text: text}

    case Ancestry.Commands.UpdatePhotoComment.new(attrs) do
      {:ok, command} ->
        socket.assigns.current_scope
        |> Ancestry.Bus.dispatch(command)
        |> handle_dispatch_result(socket)
        |> clear_edit_state_on_success()

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    comment = Comments.get_photo_comment!(socket.assigns.editing_comment_id)

    {:noreply,
     socket
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_form, nil)
     |> stream_insert(:comments, comment)}
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    command =
      Ancestry.Commands.DeletePhotoComment.new!(%{
        photo_comment_id: String.to_integer(id)
      })

    socket.assigns.current_scope
    |> Ancestry.Bus.dispatch(command)
    |> handle_dispatch_result(socket)
  end

  defp clear_edit_state_on_success({:noreply, socket}) do
    if socket.assigns[:editing_comment_id] do
      {:noreply,
       socket
       |> assign(:editing_comment_id, nil)
       |> assign(:edit_form, nil)}
    else
      {:noreply, socket}
    end
  end

  defp handle_dispatch_result({:ok, _result}, socket) do
    changeset = Comments.change_photo_comment(%PhotoComment{})
    {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
  end

  defp handle_dispatch_result({:error, :validation, changeset}, socket) do
    {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
  end

  defp handle_dispatch_result({:error, :unauthorized}, socket) do
    {:noreply, put_flash(socket, :error, gettext("You don't have permission to do that."))}
  end

  defp handle_dispatch_result({:error, :not_found}, socket) do
    {:noreply, put_flash(socket, :error, gettext("That comment no longer exists."))}
  end

  defp handle_dispatch_result({:error, :conflict, _term}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       gettext("That action conflicted with another change. Please retry.")
     )}
  end

  defp handle_dispatch_result({:error, :handler, term}, socket) do
    require Logger
    Logger.error("command failed", error: inspect(term))
    {:noreply, put_flash(socket, :error, gettext("Something went wrong."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="photo-comments-panel" class="flex flex-col h-full p-2.5 gap-2 text-white">
      <%!-- Section title row --%>
      <div class="flex items-center gap-2 px-1 shrink-0">
        <h4 class="text-xs font-cm-display font-bold text-white/90 tracking-wide uppercase">
          {gettext("Comments")}
        </h4>
        <span
          :if={@stream_count_comments > 0}
          class="text-[11px] text-white/50 bg-white/[0.10] px-1.5 py-0.5 rounded-full"
        >
          {@stream_count_comments}
        </span>
      </div>

      <%!-- Scrollable comment list --%>
      <div class="flex-1 overflow-y-auto min-h-0 px-1">
        <div id="comments-list" phx-update="stream" class="flex flex-col gap-1">
          <div id="comments-empty" class="hidden only:block text-center py-8 text-white/50">
            <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-white/[0.04] mb-2">
              <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 text-white/40" />
            </div>
            <p class="text-[12.5px] leading-snug">
              {gettext("No comments yet. Be the first to add one.")}
            </p>
          </div>

          <div :for={{id, comment} <- @streams.comments} id={id} class="group relative">
            <%= if @editing_comment_id == comment.id do %>
              <.form
                for={@edit_form}
                id={"edit-comment-#{comment.id}"}
                phx-submit="save_edit"
                phx-target={@myself}
                class="space-y-2 p-1.5"
              >
                <textarea
                  name="comment[text]"
                  id={"edit-comment-text-#{comment.id}"}
                  rows="2"
                  class="w-full bg-white/[0.10] rounded-cm px-3 py-2 text-sm text-white placeholder-white/40 focus:outline-none focus:bg-white/[0.16] resize-none"
                  phx-mounted={JS.dispatch("focus", to: "#edit-comment-text-#{comment.id}")}
                >{Phoenix.HTML.Form.normalize_value("textarea", Ecto.Changeset.get_field(@edit_form.source, :text))}</textarea>
                <div class="flex items-center gap-2">
                  <button
                    type="submit"
                    class="px-3 py-1 bg-cm-coral hover:bg-cm-coral/80 text-white font-cm-mono text-[10px] font-bold uppercase tracking-wider rounded-cm transition-colors"
                  >
                    {gettext("Save")}
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    phx-target={@myself}
                    class="px-3 py-1 bg-white/[0.10] hover:bg-white/[0.16] text-white/80 font-cm-mono text-[10px] font-bold uppercase tracking-wider rounded-cm transition-colors"
                  >
                    {gettext("Cancel")}
                  </button>
                </div>
              </.form>
            <% else %>
              <%!-- Mobile: ultra-compact inline with tap-to-select --%>
              <div
                {test_id("mobile-comment-list")}
                class={[
                  "flex gap-2 items-start py-1.5 px-1.5 rounded-cm md:hidden transition-colors",
                  @selected_comment_id == comment.id && "bg-white/[0.16]"
                ]}
                phx-click="select_comment"
                phx-value-id={comment.id}
                phx-target={@myself}
              >
                <.user_avatar account={comment.account} size={:sm} class="mt-0.5" />
                <div class="flex-1 min-w-0">
                  <p class="text-[13px] text-white/85 leading-snug break-words">
                    <span class="font-semibold text-white/95">
                      {display_first_name(comment.account)}
                    </span>
                    <span phx-no-format class="whitespace-pre-line">{comment.text}</span>
                    <span class="text-[10px] text-white/40">
                      {format_short_time(comment.inserted_at)}
                    </span>
                  </p>
                  <%= if @selected_comment_id == comment.id do %>
                    <div class="flex items-center gap-2 mt-2">
                      <.comment_actions
                        comment={comment}
                        current_scope={@current_scope}
                        myself={@myself}
                      />
                    </div>
                  <% end %>
                </div>
              </div>

              <%!-- Desktop: bubble style with floating hover actions --%>
              <div {test_id("desktop-comment-list")} class="hidden md:flex gap-2 items-start py-1">
                <.user_avatar account={comment.account} size={:sm} class="mt-0.5" />
                <div class="flex-1 min-w-0">
                  <div class="flex items-baseline gap-1.5">
                    <span class="text-xs font-semibold text-white/95">
                      {display_name(comment.account)}
                    </span>
                    <time class="text-[10px] text-white/40">
                      {format_relative_time(comment.inserted_at)}
                    </time>
                  </div>
                  <div class="bg-white/[0.10] rounded-cm px-2.5 py-1.5 inline-block max-w-full mt-0.5">
                    <p
                      phx-no-format
                      class="text-[13px] text-white/85 leading-snug break-words whitespace-pre-line"
                    >{comment.text}</p>
                  </div>
                </div>
                <%!-- Floating actions at top-right of comment row, absolute to outer group --%>
                <div class="absolute top-0 right-0 flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity bg-white/[0.16] rounded-md shadow-lg px-1 py-0.5">
                  <.comment_actions comment={comment} current_scope={@current_scope} myself={@myself} />
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Composer — L3 tonal block, transparent textarea inside --%>
      <div class="shrink-0">
        <.form
          for={@form}
          id="new-comment-form"
          phx-submit="save_comment"
          phx-target={@myself}
          class="bg-white/[0.10] rounded-cm px-3 py-1.5 flex items-end gap-2"
        >
          <textarea
            name="comment[text]"
            id="new-comment-text"
            phx-hook="TextareaAutogrow"
            rows="1"
            placeholder={gettext("Add a comment...")}
            class="flex-1 bg-transparent border-0 px-0 py-2 text-sm leading-5 text-white placeholder-white/40 focus:outline-none focus:ring-0 resize-none overflow-y-auto max-h-[180px]"
          >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
          <button
            type="submit"
            class="h-8 w-8 flex items-center justify-center bg-cm-coral hover:bg-cm-coral/80 text-white rounded-cm transition-colors shrink-0 mb-1"
            title={gettext("Post comment")}
          >
            <.icon name="hero-paper-airplane" class="w-4 h-4" />
          </button>
        </.form>
      </div>
    </div>
    """
  end

  defp comment_actions(assigns) do
    ~H"""
    <%= if can_edit?(@comment, @current_scope) do %>
      <button
        phx-click="edit_comment"
        phx-value-id={@comment.id}
        phx-target={@myself}
        class="p-1.5 rounded-md text-white/60 hover:text-white bg-white/[0.10] hover:bg-white/[0.16] transition-colors"
        title={gettext("Edit comment")}
      >
        <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
      </button>
    <% end %>
    <%= if can_delete?(@comment, @current_scope) do %>
      <button
        phx-click="delete_comment"
        phx-value-id={@comment.id}
        phx-target={@myself}
        data-confirm={gettext("Delete this comment?")}
        class="p-1.5 rounded-md text-white/60 hover:text-red-400 bg-white/[0.10] hover:bg-white/[0.16] transition-colors"
        title={gettext("Delete comment")}
      >
        <.icon name="hero-trash" class="w-3.5 h-3.5" />
      </button>
    <% end %>
    """
  end

  defp can_edit?(comment, scope) do
    can?(scope, :update, PhotoComment) and
      comment.account_id != nil and
      comment.account_id == scope.account.id
  end

  defp can_delete?(comment, scope) do
    can?(scope, :delete, PhotoComment) and
      (comment.account_id == scope.account.id or scope.account.role == :admin)
  end

  defp display_name(nil), do: gettext("Unknown")
  defp display_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{email: email}), do: email

  defp display_first_name(nil), do: gettext("Unknown")

  defp display_first_name(%{name: name}) when is_binary(name) and name != "" do
    name |> String.split() |> List.first()
  end

  defp display_first_name(%{email: email}), do: email

  defp format_short_time(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> gettext("now")
      diff < 3600 -> gettext("%{count}m", count: div(diff, 60))
      diff < 86400 -> gettext("%{count}h", count: div(diff, 3600))
      diff < 604_800 -> gettext("%{count}d", count: div(diff, 86400))
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp format_relative_time(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> gettext("just now")
      diff < 3600 -> gettext("%{count}m ago", count: div(diff, 60))
      diff < 86400 -> gettext("%{count}h ago", count: div(diff, 3600))
      diff < 604_800 -> gettext("%{count}d ago", count: div(diff, 86400))
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
