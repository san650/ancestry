# Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder landing page with a polished, left-aligned editorial page that describes the service, links to login, and shows a "Registration coming soon" note.

**Architecture:** Single-template change for the landing page content, plus a small router edit to comment out the registration route and a controller tweak for the page title. An E2E test covers the user flow.

**Tech Stack:** Phoenix controller (not LiveView), HEEx templates, Tailwind CSS with design system tokens from `DESIGN.md`.

**Spec:** `docs/superpowers/specs/2026-03-26-landing-page-design.md`

---

### Task 1: Comment out the registration route

**Files:**
- Modify: `lib/web/router.ex:100`

- [ ] **Step 1: Comment out the registration LiveView route**

In `lib/web/router.ex`, inside the `:current_account` live_session, comment out the registration route. Keep the code for future use:

```elixir
# Registration temporarily disabled — uncomment when ready
# live "/accounts/register", AccountLive.Registration, :new
```

- [ ] **Step 2: Verify the app compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no errors. There may be a warning about `AccountLive.Registration` being unused — that's fine since it's not deleted, just unreachable.

- [ ] **Step 3: Skip the registration tests**

The registration test file (`test/web/live/account_live/registration_test.exs`) will fail because the route no longer exists. Add `@moduletag :skip` to the module to disable it while the route is commented out:

```elixir
# At the top of the module, after `use Web.ConnCase`
@moduletag :skip
```

- [ ] **Step 4: Verify the app compiles and tests pass**

Run: `mix compile --warnings-as-errors && mix test test/web/live/account_live/registration_test.exs`
Expected: Compiles cleanly. Registration tests are skipped (not failed).

- [ ] **Step 5: Commit**

```bash
git add lib/web/router.ex test/web/live/account_live/registration_test.exs
git commit -m "Disable registration route temporarily for landing page"
```

---

### Task 2: Fix the page title suffix and update the controller

**Files:**
- Modify: `lib/web/components/layouts/root.html.heex:7`
- Modify: `lib/web/controllers/page_controller.ex:4-6`

- [ ] **Step 1: Fix the page title suffix in root layout**

In `lib/web/components/layouts/root.html.heex`, change the `live_title` suffix from `" · Phoenix Framework"` to `" · Ancestry"`:

```heex
<.live_title default="Ancestry" suffix=" · Ancestry">
  {assigns[:page_title]}
</.live_title>
```

- [ ] **Step 2: Pass page_title in the render call**

Replace the `landing` action in `lib/web/controllers/page_controller.ex`:

```elixir
def landing(conn, _args) do
  render(conn, :landing, page_title: "Welcome")
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly.

- [ ] **Step 4: Commit**

```bash
git add lib/web/components/layouts/root.html.heex lib/web/controllers/page_controller.ex
git commit -m "Fix page title suffix and pass page_title from landing action"
```

---

### Task 3: Build the landing page template

**Files:**
- Modify: `lib/web/controllers/page_html/landing.html.heex`

- [ ] **Step 1: Replace the placeholder template**

Replace the entire contents of `lib/web/controllers/page_html/landing.html.heex` with:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="flex items-center min-h-[calc(100vh-52px)] px-6 sm:pl-[20%]">
    <div class="flex flex-col gap-6 max-w-xl">
      <h1 class="font-ds-heading text-[2rem] sm:text-[3.5rem] font-extrabold leading-tight text-ds-primary">
        Organize your family's photos and history.
      </h1>

      <p class="font-ds-body text-base text-ds-on-surface-variant max-w-[480px]">
        Build galleries, connect people, and preserve what matters — all in one place.
      </p>

      <div class="flex items-center gap-4 mt-2">
        <a
          href={~p"/accounts/log-in"}
          class="inline-block bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-6 py-3 font-ds-body text-sm font-medium hover:brightness-110 transition-all focus-visible:ring-2 focus-visible:ring-ds-primary focus-visible:ring-offset-2"
        >
          Log in
        </a>
        <span class="font-ds-body text-sm text-ds-on-surface-variant">
          Registration coming soon
        </span>
      </div>
    </div>
  </div>
</Layouts.app>
```

Key design decisions reflected in this template:
- Uses `Layouts.app` wrapper (no logo duplication — header already shows logo + "Ancestry")
- Content vertically centered within `<main>` via `min-h-[calc(100vh-52px)]` (subtracting header height)
- Left-aligned with `sm:pl-[20%]` on desktop, full-width `px-6` on mobile
- Headline scales from `2rem` (mobile) to `3.5rem` (desktop) at the `sm` breakpoint
- CTA is a plain `<a>` tag styled as the primary button (navigation, not form submission)
- Machined metal gradient, sharp radius, hover brightness, focus ring per design system
- "Registration coming soon" inline next to the button

- [ ] **Step 2: Start dev server and visually verify**

Run: `iex -S mix phx.server`

Open `http://localhost:4000` in a browser (make sure you're logged out). Verify:
- Headline "Organize your family's photos and history." is large and left-aligned
- Subtext appears below in muted color
- "Log in" button has the dark gradient, links to `/accounts/log-in`
- "Registration coming soon" appears next to the button
- Content is vertically centered below the header
- On mobile viewport (~375px), headline shrinks and content is full-width
- Browser tab shows "Welcome · Ancestry"

- [ ] **Step 3: Commit**

```bash
git add lib/web/controllers/page_html/landing.html.heex
git commit -m "Build editorial landing page with login CTA"
```

---

### Task 4: Write E2E test for the landing page flow

**Files:**
- Create: `test/user_flows/landing_page_test.exs`

- [ ] **Step 1: Write the E2E test**

Create `test/user_flows/landing_page_test.exs`:

```elixir
defmodule Web.UserFlows.LandingPageTest do
  use Web.E2ECase

  # Given an anonymous user
  # When they visit the root URL
  # Then the landing page is displayed with the headline, subtext, login button,
  # and "Registration coming soon" note
  #
  # When they click the "Log in" button
  # Then they are navigated to the login page
  #
  # Given a logged-in user
  # When they visit the root URL
  # Then they are redirected to the organizations page

  test "anonymous user sees landing page and can navigate to login", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> assert_has("h1", text: "Organize your family's photos and history.")
      |> assert_has("p", text: "Build galleries, connect people, and preserve what matters")
      |> assert_has("a", text: "Log in")
      |> assert_has("span", text: "Registration coming soon")

    conn
    |> click_link("Log in")
    |> wait_liveview()
    |> assert_has("h1", text: "Log in")
  end

  test "logged-in user is redirected from landing to organizations", %{conn: conn} do
    conn
    |> log_in_e2e()
    |> visit(~p"/")
    |> wait_liveview()
    |> assert_has("h1", text: "Organizations")
  end
end
```

- [ ] **Step 2: Run the test**

Run: `mix test test/user_flows/landing_page_test.exs`
Expected: Both tests pass.

- [ ] **Step 3: Fix any failures**

If the redirect test fails, check what element or text the org index page renders and adjust the assertion. If the click test fails, verify the `<a>` tag renders correctly and `click_link` can find it.

- [ ] **Step 4: Commit**

```bash
git add test/user_flows/landing_page_test.exs
git commit -m "Add E2E test for landing page user flow"
```

---

### Task 5: Run precommit and verify everything passes

- [ ] **Step 1: Run the full precommit check**

Run: `mix precommit`
Expected: Compilation (warnings-as-errors), formatting, unused deps check, and all tests pass.

- [ ] **Step 2: Fix any issues that arise and commit**

Registration tests were already skipped in Task 1. If any other issues surface (formatting, warnings), fix them and commit:

```bash
git add -A
git commit -m "Fix precommit issues after landing page changes"
```
