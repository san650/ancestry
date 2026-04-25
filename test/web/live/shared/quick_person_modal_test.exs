defmodule Web.Shared.QuickPersonModalTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.Organizations
  alias Ancestry.People

  setup :register_and_log_in_account

  setup do
    {:ok, org} = Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Families.create_family(org, %{name: "Test Family"})
    %{org: org, family: family}
  end

  describe "with modal wrapper (default)" do
    test "renders the modal with form fields", %{conn: conn, org: org, family: family} do
      {:ok, view, html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      # Modal structure
      assert html =~ "New Person"

      # Form fields
      assert has_element?(view, "#quick-person-modal-form")
      assert has_element?(view, "#person_given_name")
      assert has_element?(view, "#person_surname")
      assert has_element?(view, "input[type='radio'][name='person[gender]'][value='female']")
      assert has_element?(view, "input[type='radio'][name='person[gender]'][value='male']")
      assert has_element?(view, "input[type='radio'][name='person[gender]'][value='other']")
      assert has_element?(view, "select#person_birth_day")
      assert has_element?(view, "select#person_birth_month")
      assert has_element?(view, "input#person_birth_year")
    end

    test "shows acquaintance checkbox by default", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      assert has_element?(view, test_id("quick-person-acquaintance-label"))
      assert has_element?(view, test_id("quick-person-acquaintance-checkbox"))
    end

    test "validates form on change", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      view
      |> form("#quick-person-modal-form", person: %{given_name: "Jane"})
      |> render_change()

      assert has_element?(view, "#quick-person-modal-form")
    end

    test "creates person with family_id and sends message to parent", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      view
      |> form("#quick-person-modal-form",
        person: %{given_name: "Alice", surname: "Smith", gender: "female"}
      )
      |> render_submit()

      # The harness LiveView receives {:person_created, person} and stores it
      html = render(view)
      assert html =~ "person_created:Alice Smith"

      # Verify person was created in the family
      members = People.list_people(family.id)
      assert Enum.any?(members, &(&1.given_name == "Alice" && &1.surname == "Smith"))
    end

    test "creates person without family when family_id is nil", %{conn: conn, org: org} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => nil}
        )

      view
      |> form("#quick-person-modal-form",
        person: %{given_name: "Bob", surname: "Jones", gender: "male"}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "person_created:Bob Jones"

      # Verify person exists in the org but not in any family
      people = People.list_people_for_org(org.id)
      assert Enum.any?(people, fn {p, _count} -> p.given_name == "Bob" end)
    end

    test "sends cancel message when cancel button is clicked", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      view
      |> element("button", "Cancel")
      |> render_click()

      html = render(view)
      assert html =~ "cancelled"
    end

    test "sends cancel message when Escape is pressed", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      # element |> render_keydown works for both phx-keydown and phx-window-keydown
      # per Phoenix LiveView docs (the element just needs the attribute on it)
      view
      |> element("#quick-person-modal")
      |> render_keydown(%{"key" => "Escape"})

      html = render(view)
      assert html =~ "cancelled"
    end

    test "sends cancel message when backdrop is clicked", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      view
      |> element("#quick-person-modal .absolute.inset-0")
      |> render_click()

      html = render(view)
      assert html =~ "cancelled"
    end

    test "creates person as acquaintance when checkbox is checked", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      view
      |> form("#quick-person-modal-form",
        person: %{given_name: "Carl", surname: "Guest", kind: "acquaintance"}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "person_created:Carl Guest"

      members = People.list_people(family.id)
      carl = Enum.find(members, &(&1.given_name == "Carl"))
      assert carl.kind == "acquaintance"
    end

    test "pre-populates given name from prefill_name", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{
            "org_id" => org.id,
            "family_id" => family.id,
            "prefill_name" => "PrefilledName"
          }
        )

      assert has_element?(view, "input#person_given_name[value='PrefilledName']")
    end
  end

  describe "without modal wrapper" do
    test "renders form without modal wrapper", %{conn: conn, org: org, family: family} do
      {:ok, view, html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{
            "org_id" => org.id,
            "family_id" => family.id,
            "show_modal_wrapper" => false
          }
        )

      # Form is rendered
      assert has_element?(view, "#quick-person-modal-form")

      # But no modal overlay
      refute html =~ "aria-modal"
      refute html =~ "New Person"
    end
  end

  describe "without acquaintance checkbox" do
    test "hides acquaintance checkbox when show_acquaintance is false", %{
      conn: conn,
      org: org,
      family: family
    } do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{
            "org_id" => org.id,
            "family_id" => family.id,
            "show_acquaintance" => false
          }
        )

      refute has_element?(view, test_id("quick-person-acquaintance-label"))
    end
  end

  describe "gender radio buttons" do
    test "no gender is selected by default", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      refute has_element?(
               view,
               "input[type='radio'][name='person[gender]'][value='female'][checked]"
             )

      refute has_element?(
               view,
               "input[type='radio'][name='person[gender]'][value='male'][checked]"
             )

      refute has_element?(
               view,
               "input[type='radio'][name='person[gender]'][value='other'][checked]"
             )
    end
  end

  describe "birth date fields" do
    test "birth date dropdowns have correct options", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      # Day dropdown has 31 options + placeholder
      assert has_element?(view, "select#person_birth_day option", "Day")
      assert has_element?(view, "select#person_birth_day option[value='1']")
      assert has_element?(view, "select#person_birth_day option[value='31']")

      # Month dropdown has 12 options + placeholder
      assert has_element?(view, "select#person_birth_month option", "Month")
      assert has_element?(view, "select#person_birth_month option[value='1']")
      assert has_element?(view, "select#person_birth_month option[value='12']")

      # Year text input
      assert has_element?(view, "input#person_birth_year[type='number']")
    end

    test "creates person with birth date", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} =
        live_isolated(conn, Web.Shared.QuickPersonModalTestLive,
          session: %{"org_id" => org.id, "family_id" => family.id}
        )

      view
      |> form("#quick-person-modal-form",
        person: %{
          given_name: "Diana",
          surname: "Prince",
          birth_day: "15",
          birth_month: "3",
          birth_year: "1990"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "person_created:Diana Prince"

      members = People.list_people(family.id)
      diana = Enum.find(members, &(&1.given_name == "Diana"))
      assert diana.birth_day == 15
      assert diana.birth_month == 3
      assert diana.birth_year == 1990
    end
  end
end

# Test harness LiveView that embeds the QuickPersonModal component
defmodule Web.Shared.QuickPersonModalTestLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    org_id = session["org_id"]
    family_id = session["family_id"]
    show_modal_wrapper = Map.get(session, "show_modal_wrapper", true)
    show_acquaintance = Map.get(session, "show_acquaintance", true)
    prefill_name = Map.get(session, "prefill_name", nil)

    {:ok,
     assign(socket,
       org_id: org_id,
       family_id: family_id,
       show_modal_wrapper: show_modal_wrapper,
       show_acquaintance: show_acquaintance,
       prefill_name: prefill_name,
       result: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @result do %>
        <div id="test-result">{@result}</div>
      <% end %>
      <.live_component
        module={Web.Shared.QuickPersonModal}
        id="quick-person-modal"
        organization_id={@org_id}
        family_id={@family_id}
        show_modal_wrapper={@show_modal_wrapper}
        show_acquaintance={@show_acquaintance}
        prefill_name={@prefill_name}
      />
    </div>
    """
  end

  @impl true
  def handle_info({:person_created, person}, socket) do
    name = Ancestry.People.Person.display_name(person)
    {:noreply, assign(socket, :result, "person_created:#{name}")}
  end

  def handle_info({:quick_person_cancelled}, socket) do
    {:noreply, assign(socket, :result, "cancelled")}
  end
end
