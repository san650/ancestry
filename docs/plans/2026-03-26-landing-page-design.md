# Landing Page Design

## Summary

A single-screen, left-aligned editorial landing page that introduces the service to anonymous visitors and directs them to log in. Uses the "Precision Authority" design system with strong typographic hierarchy.

## Decisions

- **Tone**: Clean and professional — trustworthy, functional, highlights what the product does
- **Content density**: Minimal single-screen — no scrolling needed
- **Layout**: Left-aligned editorial with content vertically centered within the main content area (below the existing header)
- **Login**: Link/button to existing `/accounts/log-in` page (no embedded form)
- **Headline**: "Organize your family's photos and history."
- **Logo**: No logo in the content area — rely on the existing `Layouts.app` header which already renders logo + "Ancestry"
- **Registration**: "Registration coming soon" text; the `/accounts/register` route is commented out in the router

## Structure

All content is left-aligned and vertically centered within `<main>` (below the header). Top to bottom:

1. **Headline** — "Organize your family's photos and history." in Manrope, ~3.5rem, weight 800, color `ds-primary` (#000000)
2. **Subtext** — "Build galleries, connect people, and preserve what matters — all in one place." in Inter regular, ~1rem, color `ds-on-surface-variant` (#444748), max-width ~480px for comfortable line length
3. **CTA button** — "Log in" as an `<a>` styled as a primary button (machined metal gradient per design system, white text, sharp `ds-sharp` radius), navigates to `/accounts/log-in`
4. **Registration note** — inline next to the button, small text in `ds-on-surface-variant`: "Registration coming soon"

## Styling

- **Background**: `ds-surface` (#f8f9ff), full viewport height
- **Content positioning**: Left-aligned with ~20% left offset on desktop (e.g., `pl-[20%]`), vertically centered within `<main>` via flexbox using `min-h-[calc(100vh-52px)]` (accounting for the header height) and `items-center`
- **Typography**:
  - Headline: `font-ds-heading text-[3.5rem] font-extrabold leading-tight text-ds-primary`
  - Subtext: `font-ds-body text-base text-ds-on-surface-variant`
  - Registration note: `font-ds-body text-sm text-ds-on-surface-variant`
- **Button**: Primary style — `bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-6 py-3 font-ds-body text-sm font-medium`
  - Hover: `hover:brightness-110 transition-all`
  - Focus: `focus-visible:ring-2 focus-visible:ring-ds-primary focus-visible:ring-offset-2`
- **No borders, no cards, no shadows** — typography and whitespace define the hierarchy
- **Responsive**: On mobile (`< sm`), content goes full-width with `px-6` padding, headline scales down to ~2rem. Tablet (`sm` to `lg`) uses the desktop layout with 20% offset. The subtext `max-width` constraint is removed on mobile for natural line wrapping.

## Page Title

The controller should pass `page_title: "Welcome"` so the browser tab shows "Welcome · Ancestry" instead of the default "Ancestry · Phoenix Framework".

## Route Changes

- `GET /` — no changes, already wired
- `/accounts/register` — comment out the `live` route and any links to it from the login page. Keep the code for future use.

## Files to Change

1. `lib/web/controllers/page_html/landing.html.heex` — replace the placeholder content with the new landing page design
2. `lib/web/controllers/page_controller.ex` — pass `page_title: "Welcome"` to the template
3. `lib/web/router.ex` — comment out the `/accounts/register` route
4. Check the login LiveView (`AccountLive.Login`) for any "Register" links and remove/hide them

## Out of Scope

- Registration form or flow
- Feature showcase sections
- Screenshots or illustrations
- Footer
- Dark mode styling (can be added later)
- Open Graph / SEO meta tags (can be added later)
