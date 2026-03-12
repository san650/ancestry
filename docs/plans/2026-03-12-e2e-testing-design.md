# E2E Testing Design

Date: 2026-03-12

## Overview

Add browser-based end-to-end tests using `phoenix_test_playwright` to cover features that rely on custom JavaScript and `phx-hook` interactions — things the existing LiveView integration tests cannot exercise. Tests run by default with `mix test` and can be excluded via `mix test --except e2e`.

---

## Dependencies & Installation

Add the dependency via Igniter:

```
mix igniter.install phoenix_test_playwright
```

Install Playwright and the Chromium browser into the assets directory:

```
npm --prefix assets i -D playwright
npx --prefix assets playwright install chromium --with-deps
```

---

## Configuration

**`config/test.exs`** — tell PhoenixTest which app to use and start the endpoint server:

```elixir
config :phoenix_test, otp_app: :family
config :family, Web.Endpoint, server: true
```

**`test/test_helper.exs`** — start the Playwright supervisor before `ExUnit.start()`:

```elixir
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
Application.put_env(:phoenix_test, :base_url, Web.Endpoint.url())
```

---

## `Web.E2ECase`

Lives at `test/support/e2e_case.ex`. Wraps `PhoenixTest.Playwright.Case` with `async: true` (Ecto sandbox supports concurrent browser tests), applies `@moduletag :e2e` for opt-out filtering, and provides shared helpers.

```elixir
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
```

All e2e tests `use Web.E2ECase` and receive a `conn` (a Playwright session) in the test context.

---

## Initial Test: Gallery Navigation

Lives at `test/web/e2e/gallery_navigation_test.exs`. Seeds a gallery with one processed photo via the `Galleries` context, then drives the browser through the navigation flow.

**Flow:** gallery list → click gallery card → gallery show → click photo → lightbox opens.

```elixir
defmodule Web.E2E.GalleryNavigationTest do
  use Web.E2ECase

  alias Family.Galleries

  setup do
    gallery = # create via Galleries context
    photo   = # create processed photo via Galleries context
    %{gallery: gallery, photo: photo}
  end

  test "navigate from gallery list to a gallery and open a photo", %{conn: conn, gallery: gallery} do
    conn
    |> visit(~p"/galleries")
    |> wait_liveview()
    |> click_link(gallery.name)
    |> wait_liveview()
    |> click("#photo-grid [id^='photos-']")
    |> assert_has("#lightbox")
  end
end
```

The photo must have `status: "processed"` so it renders as a clickable image card rather than a pending placeholder.

---

## Tag Strategy

Tests are tagged `@moduletag :e2e` via `Web.E2ECase`. They run by default with `mix test`. To skip them:

```
mix test --except e2e
```

The `precommit` alias is unchanged and runs all tests including e2e.

---

## Testing Notes

- `wait_liveview/1` uses `assert_has(conn, "body .phx-connected")` — Playwright waits until the selector appears, so this reliably blocks until the LiveView WebSocket is established before continuing.
- Photo cards use `phx-click` (not `<a>` tags), so `click/2` is used rather than `click_link/2`.
- The lightbox renders at `id="lightbox"` only when a photo is selected.
