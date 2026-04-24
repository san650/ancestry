# Family Live

## Print-friendly tree view

The family show page (`show.html.heex`) is print-friendly. When users print with Cmd+P / Ctrl+P, CSS `@media print` rules in `assets/css/app.css` hide all application chrome and display only the family name and text-only person cards with SVG connectors.

**When adding new features to the family show page**, ensure they are hidden from print output. Use `print:hidden` (Tailwind) on new elements, or add a `display: none !important` rule in the `@media print` block in `app.css`. Only elements that are part of the printed tree (family name, person cards, connector lines) should be visible in print.
