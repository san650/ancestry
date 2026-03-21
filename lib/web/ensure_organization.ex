defmodule Web.EnsureOrganization do
  @moduledoc """
  LiveView on_mount hook that reads the org_id argument and assigns the organization
  to the socket.

  If the organization doesn't exist it raises an error.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, params, _session, socket) do
    organization = Ancestry.Organizations.get_organization!(params["org_id"])

    {:cont, assign(socket, :organization, organization)}
  end
end
