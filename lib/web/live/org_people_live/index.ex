defmodule Web.OrgPeopleLive.Index do
  use Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} organization={@organization}>
      <p>Org people — coming soon</p>
    </Layouts.app>
    """
  end
end
