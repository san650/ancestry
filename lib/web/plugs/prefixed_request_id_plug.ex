defmodule Web.PrefixedRequestIdPlug do
  @behaviour Plug

  alias Ancestry.Prefixes
  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    request_id = Prefixes.generate(:request)

    metadata =
      case Plug.Conn.get_req_header(conn, "x-request-id") do
        [inbound | _] when byte_size(inbound) > 0 ->
          [request_id: request_id, inbound_request_id: inbound]

        _ ->
          [request_id: request_id]
      end

    Logger.metadata(metadata)

    conn
    |> Plug.Conn.put_resp_header("x-request-id", request_id)
    |> Plug.Conn.assign(:request_id, request_id)
  end
end
