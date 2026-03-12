# Test patterns

## Case modules

| Scenario | Use |
|---|---|
| Context / schema / Oban worker tests | `use Family.DataCase, async: true` |
| LiveView / controller tests | `use Web.ConnCase, async: true` + `import Phoenix.LiveViewTest` |
| Oban worker tests | also add `use Oban.Testing, repo: Family.Repo` |
| End to end tests | `use Web.E2ECase` |

Use `async: false` only when the test touches shared global state (e.g. the filesystem, real Waffle storage, or PubSub across processes that would race).

## Fixtures

Fixtures are defined as plain functions at the bottom of the test module — there is no shared factory library. Follow the existing pattern:

```elixir
def gallery_fixture(attrs \\ %{}) do
  {:ok, gallery} =
    attrs
    |> Enum.into(%{name: "Test Gallery"})
    |> Galleries.create_gallery()

  gallery
end
```

The test image at `test/fixtures/test_image.jpg` is used by Oban worker tests that exercise real ImageMagick processing.

## Data setup

Use `setup` blocks to create shared records; return them as map keys so tests receive them via pattern matching:

```elixir
setup do
  {:ok, gallery} = Galleries.create_gallery(%{name: "Test"})
  %{gallery: gallery}
end

test "does something", %{gallery: gallery} do ...
```

For temporary files needed by a test, create them under `System.tmp_dir!()` with a unique suffix and clean up with `on_exit`:

```elixir
tmp_dir = Path.join(System.tmp_dir!(), "photo_test_#{System.unique_integer([:positive])}")
File.mkdir_p!(tmp_dir)
on_exit(fn -> File.rm_rf!(tmp_dir) end)
```

## LiveView tests

Use `~p` sigil for route paths (verified routes). Navigate with `live/2`:

```elixir
{:ok, view, html} = live(conn, ~p"/galleries")
```

Interact via element selectors — always target the DOM IDs defined in the templates:

```elixir
view |> element("#open-new-gallery-btn") |> render_click()
view |> form("#new-gallery-form", gallery: %{name: "Winter 2025"}) |> render_submit()
```

Assert on element presence with `has_element?`, not raw HTML string matching:

```elixir
assert has_element?(view, "#new-gallery-modal")
refute has_element?(view, "#gallery-#{gallery.id}")
```

Raw HTML (`html =~ "..."`) is acceptable only when asserting on text content that has no stable DOM ID to target.

## Testing PubSub / real-time updates

Subscribe before triggering the action, then use `assert_receive`:

```elixir
Phoenix.PubSub.subscribe(Family.PubSub, "gallery:#{gallery.id}")
# ... trigger action ...
assert_receive {:photo_processed, ^updated}
```

To simulate a PubSub message arriving at a LiveView without going through the full pipeline, send directly to the view process:

```elixir
send(view.pid, {:photo_processed, updated_photo})
```

## Oban worker tests

Call `perform_job/2` (from `Oban.Testing`) rather than invoking `perform/1` directly, so Oban's telemetry and instrumentation fire correctly. Reserve direct `perform/1` calls for error-path tests where you need to assert on the raw return value:

```elixir
assert :ok = perform_job(ProcessPhotoJob, %{photo_id: photo.id})

# error path — direct call is fine here
assert {:error, _reason} = ProcessPhotoJob.perform(%Oban.Job{args: %{"photo_id" => photo.id}})
```

## Changeset error assertions

Use `errors_on/1` from `Family.DataCase` (available automatically) to get a readable map of errors:

```elixir
assert "can't be blank" in errors_on(changeset).name
```
