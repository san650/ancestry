defmodule Ancestry.Authorization do
  @moduledoc "Ties Permit permissions to the application."
  use Permit, permissions_module: Ancestry.Permissions

  @doc """
  Checks whether the given scope has permission to perform `action` on `resource`.

  Wraps Permit's `can/1 |> do?/2` for convenient use in templates:

      <%= if can?(@current_scope, :index, Account) do %>
        ...
      <% end %>
  """
  def can?(nil, _action, _resource), do: false

  def can?(scope, action, resource) do
    can(scope) |> do?(action, resource)
  end
end
