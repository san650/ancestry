defmodule Ancestry.Authorization do
  @moduledoc "Ties Permit permissions to the application."
  use Permit, permissions_module: Ancestry.Permissions
end
