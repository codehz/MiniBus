defmodule PacketParser do
  use MiniBus.Socket.Monad
  import MiniBus.Socket.Utils
  use MiniBus.Utils.BitString

  defp decode_list(n, data \\ [])

  defp decode_list(0, data) do
    monad do
      return(data)
    end
  end

  defp decode_list(n, data) do
    monad do
      type <- read_byte()
      value <- decode_payload_data(type)
      decode_list(n - 1, data ++ [value])
    end
  end

  defp decode_payload_data(0) do
    monad(do: return(false))
  end

  defp decode_payload_data(1) do
    monad(do: return(true))
  end

  defp decode_payload_data(2) do
    monad do
      sym <- read_shortbinary()
      return(:"#{sym}")
    end
  end

  defp decode_payload_data(3) do
    monad(do: read_dynbinary())
  end

  defp decode_payload_data(4) do
    monad(do: read_dynlength())
  end

  defp decode_payload_data(5) do
    monad do
      ret <- read_dynlength()
      return(-ret)
    end
  end

  defp decode_payload_data(6) do
    monad do
      data <- read_dynbinary()
      return({:binary, data})
    end
  end

  defp decode_payload_data(7) do
    monad do
      length <- read_dynlength()
      list <- decode_list(length)
      return(list)
    end
  end

  defp decode_payload_data(8) do
    monad do
      length <- read_dynlength()
      list <- decode_list(length)
      return(List.to_tuple(list))
    end
  end

  defp decode_payload() do
    monad do
      flag <- read_byte()
      decode_payload_data(flag)
    end
  end

  defp decode_packet_flag(0) do
    monad do
      return(:ok)
    end
  end

  defp decode_packet_flag(1) do
    monad do
      payload <- decode_payload()
      return({:ok, payload})
    end
  end

  defp decode_packet_flag(255) do
    monad do
      payload <- decode_payload()
      return({:error, payload})
    end
  end

  defp decode_packet() do
    monad do
      <<rid::32, type::binary-size(4), flag::8>> <- read_length(9)
      data <- decode_packet_flag(flag)
      return({rid, type, data})
    end
  end

  def run(socket, buffer, timeout \\ :infinity) do
    run(decode_packet(), socket, buffer, make_deadline(timeout))
  end
end

defmodule PacketParserProc do
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, {self(), socket}, debug: [:trace])
  end

  @impl GenServer
  def init({pid, socket}) do
    {:ok, {pid, socket}, {:continue, ""}}
  end

  @impl GenServer
  def handle_continue(buffer, {pid, socket}) do
    with {:ok, {rid, type, data}, buffer} <- PacketParser.run(socket, buffer) do
      send(pid, {:packet, rid, type, data})
      {:noreply, {pid, socket}, {:continue, buffer}}
    else
      {:error, e, _buffer} ->
        {:stop, e, {pid, socket}}

      {:error, e} ->
        {:stop, e, {pid, socket}}
    end
  end
end

defmodule Session do
  use GenServer
  import Bitwise

  defstruct socket: nil, reqmap: %{}

  def start_link(ip, port) do
    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false])
    :ok = :gen_tcp.send(socket, <<"MINIBUS", 0>>)
    {:ok, "OK"} = :gen_tcp.recv(socket, 2)
    GenServer.start_link(__MODULE__, socket, debug: [:trace])
  end

  @impl GenServer
  def init(socket) do
    {:ok, _pid} = PacketParserProc.start_link(socket)
    {:ok, %__MODULE__{socket: socket}}
  end

  defp encode_binary(str) when is_binary(str) do
    [encode_varuint(byte_size(str)) | str]
  end

  defp encode_binary(iodata) do
    [encode_varuint(IO.iodata_length(iodata)) | iodata]
  end

  defp encode_varuint(val) when val < 128, do: [val]
  defp encode_varuint(val), do: [<<1::1, val::7>> | encode_varuint(val >>> 7)]

  defp encode_packet(rid, command, payload) do
    [<<rid::32>>, encode_binary(command), encode_binary(payload)]
  end

  defp select_rid(reqmap) do
    condi = :rand.uniform(4_294_967_296)

    if Map.has_key?(reqmap, condi) do
      select_rid(reqmap)
    else
      condi
    end
  end

  def ping(sess, payload) do
    GenServer.call(sess, {:simple, "PING", payload})
  end

  def stop(sess) do
    GenServer.call(sess, {:simple, "STOP", <<>>})
  end

  def set_private(sess, key, value) do
    GenServer.call(sess, {:simple, "SET PRIVATE", [encode_binary(key), value]})
  end

  def get_private(sess, key) do
    GenServer.call(sess, {:simple, "GET PRIVATE", [encode_binary(key)]})
  end

  def del_private(sess, key) do
    GenServer.call(sess, {:simple, "DEL PRIVATE", [encode_binary(key)]})
  end

  def acl(sess, key, type) do
    GenServer.call(sess, {:simple, "ACL", [encode_binary(key), encode_binary(type)]})
  end

  def notify(sess, key, value) do
    GenServer.call(sess, {:simple, "NOTIFY", [encode_binary(key), value]})
  end

  def set(sess, bucket, key, value) do
    GenServer.call(sess, {:simple, "SET", [encode_binary(bucket), encode_binary(key), value]})
  end

  def del(sess, bucket, key) do
    GenServer.call(sess, {:simple, "DEL", [encode_binary(bucket), encode_binary(key)]})
  end

  def get(sess, bucket, key) do
    GenServer.call(sess, {:simple, "GET", [encode_binary(bucket), encode_binary(key)]})
  end

  def keys(sess, bucket) do
    GenServer.call(sess, {:simple, "KEYS", [encode_binary(bucket)]})
  end

  def observe(sess, callback, bucket, key) do
    GenServer.call(
      sess,
      {:event, callback, "OBSERVE", [encode_binary(bucket), encode_binary(key)]}
    )
  end

  def listen(sess, callback, bucket, key) do
    GenServer.call(
      sess,
      {:event, callback, "LISTEN", [encode_binary(bucket), encode_binary(key)]}
    )
  end

  @impl GenServer
  def handle_call({:simple, command, payload}, from, state) do
    %__MODULE__{socket: socket, reqmap: reqmap} = state
    rid = select_rid(reqmap)
    pkt = encode_packet(rid, command, payload)
    :gen_tcp.send(socket, pkt)
    {:noreply, put_in(state.reqmap[rid], {:simple, from})}
  end

  @impl GenServer
  def handle_call({:event, callback, command, payload}, from, state) do
    %__MODULE__{socket: socket, reqmap: reqmap} = state
    rid = select_rid(reqmap)
    pkt = encode_packet(rid, command, payload)
    :gen_tcp.send(socket, pkt)
    {:noreply, put_in(state.reqmap[rid], {:event, callback, from})}
  end

  @impl GenServer
  def handle_info({:packet, rid, type, data}, state) do
    %__MODULE__{reqmap: reqmap} = state

    case type do
      "RESP" ->
        with %{^rid => value} <- reqmap do
          case value do
            {:simple, from} ->
              GenServer.reply(from, data)
              reqmap = Map.delete(reqmap, rid)
              {:noreply, put_in(state.reqmap, reqmap)}

            {:event, callback, from} ->
              GenServer.reply(from, data)

              if match?(:ok, data) or match?({:ok, _}, data) do
                {:noreply, put_in(state.reqmap[rid], {:event, callback})}
              else
                reqmap = Map.delete(reqmap, rid)
                {:noreply, put_in(state.reqmap, reqmap)}
              end
          end
        end

      "NEXT" ->
        with %{^rid => value} <- reqmap do
          case value do
            {:event, callback} ->
              with {:ok, payload} <- data do
                callback.(payload)
                {:noreply, state}
              else
                {:error, _reason} ->
                  reqmap = Map.delete(reqmap, rid)
                  {:noreply, put_in(state.reqmap, reqmap)}
              end
          end
        end
    end
  end
end

port = Application.fetch_env!(:mini_bus, :port)

{:ok, sess} = Session.start_link('127.0.0.1', port)
{:ok, client} = Session.start_link('127.0.0.1', port)

Session.ping(sess, "test") |> IO.inspect(label: "ping")
Session.ping(client, "test") |> IO.inspect(label: "ping")
Session.observe(client, &IO.inspect(&1, label: "new client"), "registry", "sess")
Session.set(sess, "shared", "key", "test") |> IO.inspect(label: "set")
Session.get(sess, "shared", "key") |> IO.inspect(label: "get")
Session.keys(sess, "shared") |> IO.inspect(label: "keys")

Session.observe(sess, &IO.inspect(&1, label: "recv"), "shared", "key")
|> IO.inspect(label: "observe")

Session.set(sess, "shared", "key", "test1") |> IO.inspect(label: "set")
Session.set_private(sess, "id", "sess") |> IO.inspect(label: "set private")
Session.set(sess, "registry", "sess", "") |> IO.inspect(label: "bind")

Session.keys(sess, "registry") |> IO.inspect(label: "keys")
Session.get(sess, "registry", "sess") |> IO.inspect(label: "get")

Session.get(client, "sess", "id") |> IO.inspect(label: "get")
Session.set(client, "shared", "key", "test from client") |> IO.inspect(label: "set")
