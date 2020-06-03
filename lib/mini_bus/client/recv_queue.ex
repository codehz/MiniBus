defmodule MiniBus.Client.RecvQueue do
  use GenServer
  use TypedStruct
  use MiniBus.Utils.BitString

  typedstruct do
    field(:pid, pid(), enforce: true)
    field(:send_pid, pid(), enforce: true)
    field(:socket, port(), enforce: true)
  end

  @spec start_link(pid, port) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(send_pid, socket) do
    GenServer.start_link(__MODULE__, {self(), send_pid, socket}, [])
  end

  @impl GenServer
  @spec init({atom | pid | {atom, any} | {:via, atom, any}, any, any}) ::
          {:ok, __MODULE__.t(), {:continue, <<>>}}
  def init({pid, send_pid, socket}) do
    Process.flag(:trap_exit, true)
    :ok = MiniBus.Client.ready(pid)
    {:ok, %__MODULE__{pid: pid, send_pid: send_pid, socket: socket}, {:continue, ""}}
  end

  @impl GenServer
  def handle_info({:EXIT, e, _}, state) do
    {:stop, e, state}
  end

  @impl GenServer
  @spec handle_continue(binary, __MODULE__.t()) ::
          {:noreply, __MODULE__.t(), {:continue, binary}}
          | {:stop, any, __MODULE__.t()}
  def handle_continue(buffer, state) do
    import MiniBus.Socket.PacketDecoder

    %__MODULE__{pid: pid, send_pid: send_pid, socket: socket} = state

    with {:ok, pak, buffer} <- parse(socket, buffer),
         :ok <- process_command(send_pid, pid, pak) do
      {:noreply, state, {:continue, buffer}}
    else
      {:error, e, _buffer} ->
        {:stop, e, state}

      {:error, e} ->
        {:stop, e, state}
    end
  end

  @spec call_pid(any, pid) :: :ok
  defp call_pid(content, pid), do: GenServer.call(pid, content)

  @spec proxy_pid(function, pid) :: :ok
  defp proxy_pid(fun, pid), do: GenServer.call(pid, {:proxy, fun})

  @spec process_command(pid, pid, any) :: :ok
  defp process_command(send_pid, pid, pak)

  defp process_command(send_pid, pid, {rid, "PING", payload}) do
    {:ping, payload} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(send_pid, pid, {rid, "STOP", <<>>}) do
    :stop |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(send_pid, pid, {rid, "GET PRIVATE", BitString.match(short_binary: :key)}) do
    {:getp, key} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "SET PRIVATE", BitString.match(short_binary: :key, binary: :value)}
       ) do
    {:setp, key, value} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(send_pid, pid, {rid, "DEL PRIVATE", BitString.match(short_binary: :key)}) do
    {:delp, key} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "ACL", BitString.match(short_binary: :key, short_binary: :type)}
       ) do
    type =
      case type do
        "private" ->
          :private

        "protected" ->
          :protected

        "public" ->
          :public
      end

    {:acl, key, type} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "NOTIFY", BitString.match(short_binary: :key, binary: :value)}
       ) do
    {:notify, key, value} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "SET", BitString.match(short_binary: :bucket, short_binary: :key, binary: :value)}
       ) do
    fn -> service_command(bucket, :set, [key, value]) end
    |> proxy_pid(pid)
    |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "DEL", BitString.match(short_binary: :bucket, short_binary: :key)}
       ) do
    fn -> service_command(bucket, :del, [key]) end
    |> proxy_pid(pid)
    |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "GET", BitString.match(short_binary: :bucket, short_binary: :key)}
       ) do
    fn -> service_command(bucket, :get, [key]) end |> proxy_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "KEYS", BitString.match(short_binary: :bucket)}
       ) do
    fn -> service_command(bucket, :keys, []) end |> proxy_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "OBSERVE", BitString.match(short_binary: :bucket, short_binary: :key)}
       ) do
    {:observe, rid, bucket, key} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  defp process_command(
         send_pid,
         pid,
         {rid, "LISTEN", BitString.match(short_binary: :bucket, short_binary: :key)}
       ) do
    {:listen, rid, bucket, key} |> call_pid(pid) |> send_packet(send_pid, rid)
  end

  @spec service_command(String.t(), atom, [any]) :: any
  defp service_command(bucket, method, args) do
    with {pid, module} <- MiniBus.ServiceRegistry.lookup(bucket) do
      apply(module, method, [pid | args])
    else
      _ ->
        {:error, :bucket_not_found}
    end
  end

  defp send_packet(payload, send_pid, rid) do
    MiniBus.Client.SendQueue.send_packet(send_pid, rid, payload)
  end
end
