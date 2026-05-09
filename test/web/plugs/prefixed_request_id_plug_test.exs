defmodule Web.PrefixedRequestIdPlugTest do
  # Logger.metadata is process-global
  use ExUnit.Case, async: false
  use Plug.Test

  alias Web.PrefixedRequestIdPlug

  setup do
    Logger.metadata([])
    :ok
  end

  test "generates a req- prefixed id, sets logger metadata, sets response header" do
    conn = conn(:get, "/") |> PrefixedRequestIdPlug.call([])
    [request_id] = Plug.Conn.get_resp_header(conn, "x-request-id")

    assert <<"req-", _::binary-size(36)>> = request_id
    assert Logger.metadata()[:request_id] == request_id
    assert conn.assigns[:request_id] == request_id
  end

  test "preserves inbound x-request-id as :inbound_request_id metadata, replaces the active id" do
    conn =
      conn(:get, "/")
      |> Plug.Conn.put_req_header("x-request-id", "upstream-12345")
      |> PrefixedRequestIdPlug.call([])

    [request_id] = Plug.Conn.get_resp_header(conn, "x-request-id")
    assert <<"req-", _::binary-size(36)>> = request_id
    assert Logger.metadata()[:request_id] == request_id
    assert Logger.metadata()[:inbound_request_id] == "upstream-12345"
  end

  test "ignores empty inbound x-request-id" do
    conn =
      conn(:get, "/")
      |> Plug.Conn.put_req_header("x-request-id", "")
      |> PrefixedRequestIdPlug.call([])

    refute Logger.metadata()[:inbound_request_id]
  end
end
