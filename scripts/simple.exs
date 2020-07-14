defmodule PacketParser do
  use MiniBus.Socket.Monad
  import MiniBus.Socket.Utils
  use MiniBus.Utils.BitString

  defp decode_packet_flag(0) do
    monad do
      return({:ok, nil})
    end
  end

  defp decode_packet_flag(1) do
    monad do
      payload <- read_dynbinary()
      return({:ok, payload |> IO.inspect(label: "recv")})
    end
  end

  defp decode_packet_flag(255) do
    monad do
      payload <- read_dynbinary()
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
    GenServer.start_link(__MODULE__, {self(), socket}, debug: [])
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
  use MiniBus.Utils.BitString

  defstruct socket: nil, reqmap: %{}, handlers: %{}

  def start_link(ip, {port, _}) do
    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false])
    :ok = :gen_tcp.send(socket, <<"MINIBUS", 0>>)
    {:ok, "OK"} = :gen_tcp.recv(socket, 2)
    GenServer.start_link(__MODULE__, socket, debug: [])
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

  def register_handler(sess, name, handler) do
    GenServer.call(sess, {:register, name, handler})
  end

  def ping(sess, payload) do
    GenServer.call(sess, {:simple, "PING", payload, :binary})
  end

  def stop(sess) do
    GenServer.call(sess, {:simple, "STOP", <<>>, nil})
  end

  def set_private(sess, key, value) do
    GenServer.call(sess, {:simple, "SET PRIVATE", [encode_binary(key), value], nil})
  end

  def get_private(sess, key) do
    GenServer.call(sess, {:simple, "GET PRIVATE", [encode_binary(key)], :binary})
  end

  def del_private(sess, key) do
    GenServer.call(sess, {:simple, "DEL PRIVATE", [encode_binary(key)], nil})
  end

  def acl(sess, key, type) do
    GenServer.call(sess, {:simple, "ACL", [encode_binary(key), encode_binary(type)], nil})
  end

  def notify(sess, key, value) do
    GenServer.call(sess, {:simple, "NOTIFY", [encode_binary(key), value], nil})
  end

  def set(sess, bucket, key, value) do
    GenServer.call(
      sess,
      {:simple, "SET", [encode_binary(bucket), encode_binary(key), value], nil}
    )
  end

  def del(sess, bucket, key) do
    GenServer.call(sess, {:simple, "DEL", [encode_binary(bucket), encode_binary(key)], nil})
  end

  def get(sess, bucket, key) do
    GenServer.call(sess, {:simple, "GET", [encode_binary(bucket), encode_binary(key)], :binary})
  end

  def keys(sess, bucket) do
    GenServer.call(sess, {:simple, "KEYS", [encode_binary(bucket)], :keys})
  end

  def call(sess, bucket, key, value) do
    GenServer.call(
      sess,
      {:simple, "CALL", [encode_binary(bucket), encode_binary(key), value], :binary}
    )
  end

  def observe(sess, callback, bucket, key) do
    GenServer.call(
      sess,
      {:event, callback, "OBSERVE", [encode_binary(bucket), encode_binary(key)], nil, :binary}
    )
  end

  def listen(sess, callback, bucket, key) do
    GenServer.call(
      sess,
      {:event, callback, "LISTEN", [encode_binary(bucket), encode_binary(key)], nil, :binary}
    )
  end

  defp parse_payload(:binary, data) do
    {:ok, data}
  end

  defp parse_payload(nil, nil) do
    {:ok, nil}
  end

  defp parse_payload(nil, _data) do
    {:error, :expect_nil}
  end

  defp parse_payload(:keys, data) do
    parse_keys(data)
  end

  defp parse_keys(<<>>) do
    []
  end

  defp parse_keys(BitString.match(short_binary: :acl, short_binary: :name, binary: :rest)) do
    [{:"#{acl}", name} | parse_keys(rest)]
  end

  @impl GenServer
  def handle_call({:register, name, handler}, _from, state) do
    {:reply, :ok, put_in(state.handlers[name], handler)}
  end

  @impl GenServer
  def handle_call({:simple, command, payload, spec}, from, state) do
    %__MODULE__{socket: socket, reqmap: reqmap} = state
    rid = select_rid(reqmap)
    pkt = encode_packet(rid, command, payload)
    :gen_tcp.send(socket, pkt)
    {:noreply, put_in(state.reqmap[rid], {:simple, from, spec})}
  end

  @impl GenServer
  def handle_call({:event, callback, command, payload, spec, espec}, from, state) do
    %__MODULE__{socket: socket, reqmap: reqmap} = state
    rid = select_rid(reqmap)
    pkt = encode_packet(rid, command, payload)
    :gen_tcp.send(socket, pkt)
    {:noreply, put_in(state.reqmap[rid], {:event, callback, from, spec, espec})}
  end

  @impl GenServer
  def handle_info({:packet, rid, type, data}, state) do
    %__MODULE__{reqmap: reqmap, handlers: handlers} = state

    case type do
      "RESP" ->
        with %{^rid => value} <- reqmap do
          case value do
            {:simple, from, spec} ->
              case data do
                {:ok, payload} -> GenServer.reply(from, parse_payload(spec, payload))
                {:error, e} -> GenServer.reply(from, {:error, parse_payload(:binary, e)})
              end

              reqmap = Map.delete(reqmap, rid)
              {:noreply, put_in(state.reqmap, reqmap)}

            {:event, callback, from, spec, espec} ->
              with {:ok, payload} <- data do
                GenServer.reply(from, parse_payload(spec, payload))
                {:noreply, put_in(state.reqmap[rid], {:event, callback, espec})}
              else
                {:error, e} ->
                  GenServer.reply(from, parse_payload(:binary, e))
                  {:noreply, put_in(state.reqmap, Map.delete(reqmap, rid))}
              end
          end
        else
          _ -> {:noreply, state}
        end

      "NEXT" ->
        with %{^rid => value} <- reqmap do
          case value do
            {:event, callback, spec} ->
              with {:ok, payload} <- data do
                callback.(parse_payload(spec, payload))
                {:noreply, state}
              else
                {:error, _reason} ->
                  reqmap = Map.delete(reqmap, rid)
                  {:noreply, put_in(state.reqmap, reqmap)}
              end
          end
        else
          _ -> {:noreply, state}
        end

      "CALL" ->
        {:ok, BitString.match(short_binary: :key, binary: :value)} = data
        %__MODULE__{socket: socket} = state

        with %{^key => handler} <- handlers do
          res = handler.(value)
          pkt = encode_packet(rid, "RESPONSE", res)
          :gen_tcp.send(socket, pkt)
        else
          _ ->
            pkt = encode_packet(rid, "EXCEPTION", "not defined")
            :gen_tcp.send(socket, pkt)
        end

        {:noreply, state}
    end
  end
end

defmodule Generator do
  @alphabet Enum.concat([?0..?9, ?A..?Z, ?a..?z])

  def randstring(count) do
    :rand.seed(:exsplus, :os.timestamp())

    Stream.repeatedly(&random_char_from_alphabet/0)
    |> Enum.take(count)
    |> List.to_string()
  end

  defp random_char_from_alphabet() do
    Enum.random(@alphabet)
  end
end

listen = Application.fetch_env!(:mini_bus, :listen)

{:ok, sess} = Session.start_link('127.0.0.1', listen)
{:ok, client} = Session.start_link('127.0.0.1', listen)

Session.register_handler(sess, "test", fn _ -> Generator.randstring(300) end)

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
Session.call(client, "sess", "test", "boom") |> IO.inspect(label: "call")
Session.call(sess, "sess", "test", "boom") |> IO.inspect(label: "call")
