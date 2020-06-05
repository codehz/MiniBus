defmodule MiniBus.Client.SendQueue do
  use GenServer
  import Bitwise
  require Logger

  @spec start_link(port) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket, [])
  end

  @spec send_ready(pid) :: :ok
  def send_ready(pid) do
    GenServer.cast(pid, "OK")
  end

  @spec send_packet(pid, integer, <<_::32>>, :ok | {:error, atom} | {:ok, any}) :: :ok
  def send_packet(pid, rid, command, packet) when byte_size(command) == 4 do
    GenServer.cast(pid, [<<rid::32, command::binary>> | encode_packet(packet)])
  end

  @impl GenServer
  @spec init(port) :: {:ok, port}
  def init(socket) do
    Process.flag(:trap_exit, true)
    {:ok, socket}
  end

  @impl GenServer
  def handle_info({:EXIT, e, _}, state) do
    {:stop, e, state}
  end

  @impl GenServer
  def terminate(_, socket) do
    :gen_tcp.close(socket)
  end

  @impl GenServer
  def handle_cast(data, socket) do
    case :gen_tcp.send(socket, data) do
      :ok ->
        {:noreply, socket}

      {:error, e} ->
        {:stop, e, socket}
    end
  end

  defp encode_binary(str), do: [encode_varuint(byte_size(str)) | str]

  defp encode_varuint(val) when val < 128, do: [val]
  defp encode_varuint(val), do: [<<1::1, val::7>> | encode_varuint(val >>> 7)]

  defp encode_data(data)

  defp encode_data(false), do: [0]
  defp encode_data(true), do: [1]

  defp encode_data(data) when is_atom(data) do
    [2 | data |> Atom.to_string() |> encode_binary()]
  end

  defp encode_data(data) when is_binary(data) do
    [3 | data |> encode_binary()]
  end

  defp encode_data(data) when is_integer(data) do
    if data >= 0 do
      [4 | encode_varuint(data)]
    else
      [5 | encode_varuint(-data + 1)]
    end
  end

  defp encode_data({:binary, data}) do
    [6 | data |> encode_binary()]
  end

  defp encode_data(data) when is_list(data) do
    size = data |> length() |> encode_varuint()
    contents = Enum.map(data, &encode_data/1)

    [7, size | contents]
  end

  defp encode_data(data) when is_tuple(data) do
    list = Tuple.to_list(data)
    size = list |> length() |> encode_varuint()
    contents = Enum.map(list, &encode_data/1)

    [8, size | contents]
  end

  defp encode_data(data) do
    [255 | data |> inspect() |> encode_binary()]
  end

  defp encode_packet(pkt)

  defp encode_packet(:ok) do
    [0]
  end

  defp encode_packet({:ok, payload}) do
    [1 | payload |> encode_data()]
  end

  defp encode_packet({:error, e}) do
    [255 | e |> encode_data]
  end
end
