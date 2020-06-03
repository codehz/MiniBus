defmodule MiniBus.Client do
  use GenServer
  use TypedStruct
  @type key :: String.t()
  @type value :: binary

  typedstruct do
    field(:send_pid, pid(), enforce: true)
    field(:storage, %{Stirng.t() => binary}, enforce: true)
  end

  defmacrop foreach_name(do: expression) do
    quote do
      for var!(name) <- MiniBus.ServiceRegistry.names() do
        IO.inspect(var!(name), label: "name")
        unquote(expression)
      end
    end
  end

  @spec start_link(any, [
          {:debug, [:log | :statistics | :trace | {any, any}]}
          | {:hibernate_after, :infinity | non_neg_integer}
          | {:name, atom | {:global, any} | {:via, atom, any}}
          | {:spawn_opt,
             :link
             | :monitor
             | {:fullsweep_after, non_neg_integer}
             | {:min_bin_vheap_size, non_neg_integer}
             | {:min_heap_size, non_neg_integer}
             | {:priority, :high | :low | :normal}}
          | {:timeout, :infinity | non_neg_integer}
        ]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(socket, options \\ []) do
    GenServer.start_link(__MODULE__, socket, options)
  end

  @spec get(pid, key) :: {:error, :not_found} | {:ok, any}
  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end

  @spec del(pid, key) :: :ok
  def del(pid, key) do
    GenServer.call(pid, {:del, key})
  end

  @spec set(pid, key, value) :: :ok
  def set(pid, key, value) do
    GenServer.call(pid, {:set, key, value})
  end

  @spec keys(pid) :: {:ok, [key]}
  def keys(pid) do
    GenServer.call(pid, :keys)
  end

  @spec ready(atom | pid | {atom, any} | {:via, atom, any}) :: :ok
  def ready(pid) do
    GenServer.cast(pid, :ready)
  end

  defp direct_reply(res, state), do: {:reply, res, state}

  @impl GenServer
  @spec init(any) :: {:ok, __MODULE__.t()}
  def init(socket) do
    Process.flag(:trap_exit, true)
    {:ok, send_pid} = MiniBus.Client.SendQueue.start_link(socket)
    {:ok, _} = MiniBus.Client.RecvQueue.start_link(send_pid, socket)
    :erlang.put(:name, __MODULE__)
    {:ok, %__MODULE__{send_pid: send_pid, storage: %{}}}
  end

  @impl GenServer
  def handle_info({:EXIT, e, _}, state) do
    {:stop, e, state}
  end

  @impl GenServer
  def handle_info({:event, rid, value}, state) do
    %__MODULE__{send_pid: send_pid} = state
    MiniBus.Client.SendQueue.send_packet(send_pid, rid, {:ok, value})
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:ping, payload}, _from, state) do
    {:ok, payload} |> direct_reply(state)
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:ok, MiniBus.ServiceRegistry.keys()} |> direct_reply(state)
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    {:stop, {:shutdown, :expected}, state}
  end

  @impl GenServer
  def handle_call({:getp, key}, _from, state) do
    %__MODULE__{storage: storage} = state

    case storage do
      %{^key => tup} ->
        {:ok, tup}

      _ ->
        {:error, :not_found}
    end
    |> direct_reply(state)
  end

  @impl GenServer
  def handle_call({:delp, key}, _from, state) do
    %__MODULE__{storage: storage} = state
    :ok |> direct_reply(put_in(state.storage, Map.delete(storage, key)))
  end

  @impl GenServer
  def handle_call({:setp, key, value}, _from, state) do
    %__MODULE__{storage: storage} = state

    foreach_name do
      MiniBus.EventStream.emit({:update, name, key}, value)
    end

    storage =
      case storage do
        %{^key => tup} ->
          Map.replace!(storage, key, put_elem(tup, 1, value))

        _ ->
          Map.put_new(storage, key, {:protected, value})
      end

    :ok |> direct_reply(put_in(state.storage, storage))
  end

  @impl GenServer
  def handle_call({:acl, key, type}, _from, state) do
    %__MODULE__{storage: storage} = state

    storage =
      case storage do
        %{^key => tup} ->
          Map.replace!(storage, key, put_elem(tup, 0, type))

        _ ->
          Map.put_new(storage, key, {type, <<>>})
      end

    :ok |> direct_reply(put_in(state.storage, storage))
  end

  @impl GenServer
  def handle_call({:notify, key, value}, _from, state) do
    foreach_name do
      :ok = MiniBus.EventStream.emit({:notify, name, key}, value)
    end

    :ok |> direct_reply(state)
  end

  @impl GenServer
  def handle_call({:set, key, value}, _from, state) do
    %__MODULE__{storage: storage} = state

    case storage do
      %{^key => {acl, _value}} ->
        case acl do
          :public ->
            foreach_name do
              MiniBus.EventStream.emit({:update, name, key}, value)
            end

            storage = Map.replace!(storage, key, {:public, value})
            :ok |> direct_reply(put_in(state.storage, storage))

          :protected ->
            {:error, :not_allowed} |> direct_reply(state)

          :private ->
            {:error, :not_found} |> direct_reply(state)
        end

      _ ->
        {:error, :not_found} |> direct_reply(state)
    end
  end

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    %__MODULE__{storage: storage} = state

    case storage do
      %{^key => {_acl, value}} ->
        {:ok, value}

      _ ->
        {:error, :not_found}
    end
    |> direct_reply(state)
  end

  @impl GenServer
  def handle_call({:del, key}, _from, state) do
    %__MODULE__{storage: storage} = state

    storage = Map.delete(storage, key)
    :ok |> direct_reply(put_in(state.storage, storage))
  end

  @impl GenServer
  def handle_call(:keys, _from, state) do
    %__MODULE__{storage: storage} = state

    res =
      for {key, {acl, _value}} <- storage do
        {acl, key}
      end

    {:ok, res} |> direct_reply(state)
  end

  @impl GenServer
  def handle_call({flag, rid, bucket, key}, _from, state) when flag == :observe or flag == :listen do
    {:ok, _pid} = MiniBus.EventStream.listen({flag, bucket, key}, rid)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:proxy, fun}, _from, state) do
    {:reply, fun.(), state}
  end

  @impl GenServer
  def handle_cast(:ready, state) do
    MiniBus.Client.SendQueue.send_ready(state.send_pid)
    {:noreply, state}
  end
end
