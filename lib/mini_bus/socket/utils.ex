defmodule MiniBus.Socket.Utils do
  use MiniBus.Socket.Monad
  import Bitwise

  defp try_decode_varuint(data) when is_binary(data), do: do_decode_varuint(0, 0, data)

  defp do_decode_varuint(result, shift, <<0::1, byte::7, rest::binary>>) do
    {result ||| byte <<< shift, rest}
  end

  defp do_decode_varuint(result, shift, <<1::1, byte::7, rest::binary>>) do
    do_decode_varuint(
      result ||| byte <<< shift,
      shift + 7,
      rest
    )
  end

  defp do_decode_varuint(_result, _shift, _data), do: :truncated

  defp socket_read_varuint(socket, buffer, deadline) do
    case try_decode_varuint(buffer) do
      {result, buffer} ->
        {:ok, result, buffer}

      :truncated ->
        with {:ok, next} <- :gen_tcp.recv(socket, 0, calc_timeout(deadline)) do
          socket_read_varuint(socket, buffer <> next, deadline)
        else
          {:error, e} -> {:error, e, buffer}
        end
    end
  end

  defp _read_length(socket, size, buffer, deadline) do
    if byte_size(buffer) < size do
      with {:ok, next} <- :gen_tcp.recv(socket, 0, calc_timeout(deadline)) do
        _read_length(socket, size, buffer <> next, deadline)
      end
    else
      <<result::binary-size(size), rest::binary>> = buffer
      {:ok, result, rest}
    end
  end

  @spec read_length(integer) :: {:cont, (any -> any)}
  def read_length(size) do
    monad(do: wrap(&_read_length(&1, size, &2, &3)))
  end

  @spec read_byte :: {:cont, (any -> any)}
  def read_byte() do
    monad do
      <<byte>> <- read_length(1)
      return(byte)
    end
  end

  @spec read_shortbinary :: {:cont, (any -> any)}
  def read_shortbinary() do
    monad do
      len <- read_byte()
      read_length(len)
    end
  end

  @spec read_dynlength :: {:cont, (any -> any)}
  def read_dynlength() do
    monad(do: wrap(&socket_read_varuint/3))
  end

  @spec read_dynbinary :: {:cont, (any -> any)}
  def read_dynbinary() do
    monad do
      len <- read_dynlength()
      read_length(len)
    end
  end
end
