defmodule MiniBus.Socket.PacketDecoder do
  use MiniBus.Socket.Monad
  import MiniBus.Socket.Utils

  defp parse_req_id() do
    monad do
      <<id::32>> <- read_length(4)
      return(id)
    end
  end

  defp parse_command(), do: read_shortbinary()

  defp parse_payload(), do: read_dynbinary()

  @spec parse(port, binary, :infinity | integer) :: {:ok, {integer, String.t, binary}, binary} | {:error, any, binary}
  def parse(socket, buffer, timeout \\ :infinity) do
    run(
      monad do
        req_id <- parse_req_id()
        command <- parse_command()
        payload <- parse_payload()
        return({req_id, command, payload})
      end,
      socket,
      buffer,
      make_deadline(timeout)
    )
  end
end
