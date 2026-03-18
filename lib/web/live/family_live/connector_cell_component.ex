defmodule Web.FamilyLive.ConnectorCellComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative w-full h-full min-h-[2rem]">
      <%= case @type do %>
        <% :vertical -> %>
          <div class="absolute left-1/2 top-0 bottom-0 w-0 border-l-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% :horizontal -> %>
          <div class="absolute top-1/2 left-0 right-0 h-0 border-t-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% :t_down -> %>
          <div class="absolute top-1/2 left-0 right-0 h-0 border-t-2 border-zinc-300 dark:border-zinc-600">
          </div>
          <div class="absolute left-1/2 top-1/2 bottom-0 w-0 border-l-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% :top_left -> %>
          <div class="absolute top-1/2 left-0 right-1/2 h-0 border-t-2 border-zinc-300 dark:border-zinc-600">
          </div>
          <div class="absolute left-1/2 top-1/2 bottom-0 w-0 border-l-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% :top_right -> %>
          <div class="absolute top-1/2 left-1/2 right-0 h-0 border-t-2 border-zinc-300 dark:border-zinc-600">
          </div>
          <div class="absolute left-1/2 top-1/2 bottom-0 w-0 border-l-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% :bottom_left -> %>
          <div class="absolute top-0 left-1/2 h-1/2 w-0 border-l-2 border-zinc-300 dark:border-zinc-600">
          </div>
          <div class="absolute top-1/2 left-0 right-1/2 h-0 border-t-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% :bottom_right -> %>
          <div class="absolute top-0 left-1/2 h-1/2 w-0 border-l-2 border-zinc-300 dark:border-zinc-600">
          </div>
          <div class="absolute top-1/2 left-1/2 right-0 h-0 border-t-2 border-zinc-300 dark:border-zinc-600">
          </div>
        <% _ -> %>
          <%!-- unknown connector type, render nothing --%>
      <% end %>
    </div>
    """
  end
end
