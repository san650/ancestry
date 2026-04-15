defmodule Web.Plugs.LocaleTest do
  use Web.ConnCase, async: true

  alias Ancestry.Identity.Scope

  describe "call/2" do
    test "uses account locale when logged in", %{conn: conn} do
      account = insert(:account, locale: "es-UY")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:current_scope, Scope.for_account(account))
        |> Web.Plugs.Locale.call([])

      assert conn.assigns.locale == "es-UY"
      assert get_session(conn, "locale") == "es-UY"
    end

    test "uses session locale when not logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"locale" => "es-UY"})
        |> assign(:current_scope, Scope.for_account(nil))
        |> Web.Plugs.Locale.call([])

      assert conn.assigns.locale == "es-UY"
    end

    test "parses Accept-Language header for Spanish", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> assign(:current_scope, Scope.for_account(nil))
        |> put_req_header("accept-language", "es-AR,es;q=0.9")
        |> Web.Plugs.Locale.call([])

      assert conn.assigns.locale == "es-UY"
    end

    test "parses bare 'en' Accept-Language header", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> assign(:current_scope, Scope.for_account(nil))
        |> put_req_header("accept-language", "en")
        |> Web.Plugs.Locale.call([])

      assert conn.assigns.locale == "en-US"
    end

    test "defaults to en-US when no locale info", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> assign(:current_scope, Scope.for_account(nil))
        |> Web.Plugs.Locale.call([])

      assert conn.assigns.locale == "en-US"
      assert get_session(conn, "locale") == "en-US"
    end

    test "ignores unsupported account locale and falls back", %{conn: conn} do
      account = insert(:account, locale: "fr-FR")

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:current_scope, Scope.for_account(account))
        |> Web.Plugs.Locale.call([])

      assert conn.assigns.locale == "en-US"
    end
  end
end
