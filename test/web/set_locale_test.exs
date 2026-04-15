defmodule Web.SetLocaleTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "on_mount/4" do
    test "sets locale from logged-in account", %{conn: conn} do
      account = insert(:account, locale: "es-UY")
      conn = log_in_account(conn, account)

      {:ok, _view, _html} = live(conn, ~p"/accounts/settings")

      assert Gettext.get_locale(Web.Gettext) == "es-UY"
    end

    test "sets locale from session for logged-out user", %{conn: conn} do
      conn = conn |> init_test_session(%{"locale" => "es-UY"})

      {:ok, _view, _html} = live(conn, ~p"/accounts/log-in")

      assert Gettext.get_locale(Web.Gettext) == "es-UY"
    end

    test "defaults to en-US when no locale info", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/accounts/log-in")

      assert Gettext.get_locale(Web.Gettext) == "en-US"
    end
  end
end
