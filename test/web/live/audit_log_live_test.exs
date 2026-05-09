defmodule Web.AuditLogLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ancestry.Factory

  setup do
    admin = insert(:account, role: :admin)
    %{conn: log_in_account(build_conn(), admin), admin: admin}
  end

  test "prepends new row when {:audit_logged, row} arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/audit-log")

    new_row =
      build(:audit_log,
        id: 999_999,
        account_email: "live@example.com",
        command_module: "Ancestry.Commands.AddCommentToPhoto",
        inserted_at: NaiveDateTime.utc_now()
      )

    send(view.pid, {:audit_logged, new_row})

    assert render(view) =~ "live@example.com"
  end

  test "discards row that doesn't match active organization filter", %{conn: conn} do
    org = insert(:organization)
    {:ok, view, _html} = live(conn, ~p"/admin/audit-log?organization_id=#{org.id}")

    other_org_row =
      build(:audit_log,
        id: 999_998,
        organization_id: org.id + 1,
        account_email: "other@x.com"
      )

    send(view.pid, {:audit_logged, other_org_row})

    refute render(view) =~ "other@x.com"
  end
end
