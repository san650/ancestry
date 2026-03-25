# Bugfix: Header links (username, settings, logout) not visible

## Bug Description

The username, settings, and logout links defined in `Web.Layouts.app/1` do not appear in the header on any authenticated page.

## Root Cause

The `Layouts.app` component requires `current_scope` to be passed as an attr to render the account links. The attr has `default: nil`, so when omitted the conditional `if @current_scope && @current_scope.account` evaluates to false and the links are never rendered.

All 12 main app templates call `<Layouts.app flash={@flash} ...>` without passing `current_scope`. Only the account-related LiveViews (login, registration, settings, confirmation) pass it.

## Fix

Add `current_scope={@current_scope}` to every `<Layouts.app>` call missing it. All affected templates are in authenticated `live_session`s with `on_mount: [{Web.AccountAuth, :require_authenticated}]`, so `@current_scope` is always assigned on the socket.

### Affected files

1. `lib/web/live/organization_live/index.html.heex`
2. `lib/web/live/people_live/index.html.heex`
3. `lib/web/live/gallery_live/show.html.heex`
4. `lib/web/live/gallery_live/index.html.heex`
5. `lib/web/live/family_live/index.html.heex`
6. `lib/web/live/person_live/show.html.heex`
7. `lib/web/live/family_live/show.html.heex`
8. `lib/web/live/family_live/new.html.heex`
9. `lib/web/live/person_live/index.html.heex`
10. `lib/web/live/kinship_live.html.heex`
11. `lib/web/live/person_live/new.html.heex`
12. `lib/web/live/org_people_live/index.html.heex`

## Verification

- `mix precommit` passes (compile, format, tests)
- Header shows email, Settings link, and Log out link on all authenticated pages
