defmodule Web.AccountManagementLive.Edit do
  use Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <p>Edit account coming soon.</p>
    </Layouts.app>
    """
  end
end
