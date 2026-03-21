defmodule Web.FamilyLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    %{org: org}
  end

  test "happy path", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/new")

    cover =
      file_input(view, "#new-family-form", :cover, [
        %{
          name: "cover.jpg",
          content: Path.absname("test/fixtures/test_image.jpg"),
          type: "image/jpeg"
        }
      ])

    assert render_upload(cover, "cover.jpg") =~ "100%"

    result =
      view
      |> form("#new-family-form", family: %{name: "The Johnsons"})
      |> render_submit()

    {:ok, show_view, _html} = follow_redirect(result, conn)

    assert has_element?(show_view, "div", "The Johnsons")
  end

  test "renders new family form", %{conn: conn, org: org} do
    {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/families/new")
    assert html =~ "New Family"
    assert html =~ "new-family-form"
  end

  test "creates a family with valid name", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/new")

    view
    |> form("#new-family-form", family: %{name: "The Johnsons"})
    |> render_submit()

    [family] = Families.list_families(org.id)
    assert family.name == "The Johnsons"
  end

  test "shows validation error for blank name", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/new")

    view
    |> form("#new-family-form", family: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#new-family-form .text-error")
  end
end
