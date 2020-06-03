defmodule MiniBus.Builtin.Shared do
  use GenServer
  @name "shared"
  @type key :: String.t()
  @type value :: binary

  @spec start_link([
          {:debug, [:log | :statistics | :trace | {any, any}]}
          | {:hibernate_after, :infinity | non_neg_integer}
          | {:spawn_opt,
             :link
             | :monitor
             | {:fullsweep_after, non_neg_integer}
             | {:min_bin_vheap_size, non_neg_integer}
             | {:min_heap_size, non_neg_integer}
             | {:priority, :high | :low | :normal}}
          | {:timeout, :infinity | non_neg_integer}
        ]) :: :ignore | {:error, any} | {:ok, pid}
  @doc """
  Starts the kv
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__} | opts])
  end

  @spec get(pid, key) :: {:error, :not_found} | {:ok, any}
  def get(_pid, key) do
    case :ets.lookup(__MODULE__, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @spec set(pid, key, value) :: :ok
  def set(_pid, key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  @spec del(pid, key) :: :ok
  def del(_pid, key) do
    GenServer.call(__MODULE__, {:del, key})
  end

  @spec keys(pid) :: {:ok, [key]}
  def keys(_pid) do
    {:ok, :ets.select(__MODULE__, [{{:"$1", :_}, [], [{{:public, :"$1"}}]}])}
  end

  @spec request(pid, key, value) :: {:error, :impossible}
  def request(_pid, _key, _value) do
    {:error, :impossible}
  end

  @impl GenServer
  @spec init(:ok) :: {:ok, atom | :ets.tid()}
  def init(:ok) do
    MiniBus.ServiceRegistry.register(@name, __MODULE__)
    {:ok, :ets.new(__MODULE__, [:named_table, :protected, read_concurrency: true])}
  end

  @impl GenServer
  def handle_call({:set, key, value}, _from, state) do
    :ets.insert(__MODULE__, {key, value})
    MiniBus.EventStream.emit({:update, @name, key}, value)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:del, key}, _from, state) do
    :ets.delete(__MODULE__, key)
    {:reply, :ok, state}
  end
end
