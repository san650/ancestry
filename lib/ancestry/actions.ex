defmodule Ancestry.Actions do
  @moduledoc "Permit actions — auto-discovers live_actions from the router."
  use Permit.Phoenix.Actions, router: Web.Router
end
