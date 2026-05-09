defmodule Ancestry.AuditTest do
  use Ancestry.DataCase, async: true
  alias Ancestry.Audit

  describe "list_entries/2" do
    test "returns rows newest first" do
      old = insert(:audit_log, inserted_at: ~N[2026-05-01 10:00:00])
      new = insert(:audit_log, inserted_at: ~N[2026-05-09 10:00:00])

      assert [r1, r2] = Audit.list_entries(%{}, 50)
      assert r1.id == new.id
      assert r2.id == old.id
    end

    test "filters by organization_id" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      a = insert(:audit_log, organization_id: org_a.id)
      _b = insert(:audit_log, organization_id: org_b.id)

      assert [row] = Audit.list_entries(%{organization_id: org_a.id}, 50)
      assert row.id == a.id
    end

    test "filters by account_id" do
      acc = insert(:account)
      mine = insert(:audit_log, account_id: acc.id)
      _other = insert(:audit_log, account_id: acc.id + 9999)

      assert [row] = Audit.list_entries(%{account_id: acc.id}, 50)
      assert row.id == mine.id
    end

    test "respects limit" do
      Enum.each(1..5, fn _ -> insert(:audit_log) end)
      assert length(Audit.list_entries(%{}, 3)) == 3
    end

    test "cursor returns strictly older rows" do
      r1 = insert(:audit_log, inserted_at: ~N[2026-05-09 10:00:00])
      r2 = insert(:audit_log, inserted_at: ~N[2026-05-08 10:00:00])
      r3 = insert(:audit_log, inserted_at: ~N[2026-05-07 10:00:00])

      cursor = {r1.inserted_at, r1.id}

      ids = Audit.list_entries(%{before: cursor}, 50) |> Enum.map(& &1.id)
      assert ids == [r2.id, r3.id]
    end

    test "cursor with same-timestamp rows uses id as tiebreaker" do
      ts = ~N[2026-05-09 10:00:00]
      a = insert(:audit_log, inserted_at: ts)
      b = insert(:audit_log, inserted_at: ts)
      [first, second] = if a.id < b.id, do: [b, a], else: [a, b]

      cursor = {first.inserted_at, first.id}
      assert [row] = Audit.list_entries(%{before: cursor}, 50)
      assert row.id == second.id
    end
  end
end
