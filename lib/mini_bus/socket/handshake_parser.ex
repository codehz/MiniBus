defmodule MiniBus.Socket.HandshakeParser do
  use MiniBus.Socket.Monad
  import MiniBus.Socket.Utils
  use MiniBus.Utils.BitString

  defp parse_magic() do
    monad do
      str <- read_length(8)

      if str == BitString.match(static: "MINIBUS", static: 0) do
        return(:ok)
      else
        fail(:mismatch)
      end
    end
  end

  defp expect_empty() do
    monad do
      buffer <- get_buffer()

      if byte_size(buffer) == 0 do
        return(:ok)
      else
        fail(:tailling)
      end
    end
  end

  @spec parse(port, :infinity | number) :: {:ok, any, binary} | {:error, any, binary}
  def parse(socket, timeout) do
    run(
      parse_magic() >>> expect_empty(),
      socket,
      "",
      make_deadline(timeout)
    )
  end
end
