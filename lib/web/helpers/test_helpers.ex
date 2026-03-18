defmodule Web.Helpers.TestHelpers do
  @moduledoc """
  Provides `test_id/1` which emits `data-testid` attributes in dev/test only.
  In production, returns an empty list so no test attributes appear in HTML.

  Usage in templates:

      <button {test_id("family-new-btn")} phx-click="...">New Family</button>
  """

  if Mix.env() in [:dev, :test] do
    def test_id(id), do: [{"data-testid", id}]
  else
    def test_id(_id), do: []
  end
end
