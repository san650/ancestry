defmodule Web.E2ECase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use PhoenixTest.Playwright.Case, async: true
      @moduletag :e2e
      import Web.E2ECase
    end
  end

  def wait_liveview(conn) do
    PhoenixTest.assert_has(conn, "body .phx-connected")
  end
end
