defmodule Web.EnsureOrganization do
  @moduledoc """
  LiveView on_mount hook that reads the org_id argument, assigns the organization
  to the socket, and verifies the current account has access.

  Admins access all organizations. Non-admins must have an account_organizations
  record. Returns the same error message for "not found" and "not authorized"
  to avoid leaking org existence.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]

  def on_mount(:default, params, _session, socket) do
    account = socket.assigns.current_scope.account

    case Ancestry.Organizations.get_organization(params["org_id"]) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Organization doesn't exist")
         |> push_navigate(to: "/org")}

      organization ->
        if Ancestry.Organizations.account_has_org_access?(account, organization.id) do
          scope = %{socket.assigns.current_scope | organization: organization}
          {:cont, assign(socket, :current_scope, scope)}
        else
          {:halt,
           socket
           |> put_flash(:error, "Organization doesn't exist")
           |> push_navigate(to: "/org")}
        end
    end
  end
end
