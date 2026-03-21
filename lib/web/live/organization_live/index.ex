defmodule Web.OrganizationLive.Index do
  use Web, :live_view

  alias Ancestry.Organizations

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :organizations, Organizations.list_organizations())}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}
end
