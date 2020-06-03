defmodule MiniBus.Builtin.RegistryProxy do
  use GenServer
  @type key :: String.t()
  @type value :: binary
  @name "registry"

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
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__} | opts])
  end

  @impl GenServer
  @spec init(:ok) :: {:ok, atom | :ets.tid()}
  def init(:ok) do
    MiniBus.ServiceRegistry.register(@name, __MODULE__)
    {:ok, nil}
  end

  @spec get(pid, key) :: {:error, :not_found} | {:ok, any}
  def get(_pid, key) do
    with {_pid, mod} <- MiniBus.ServiceRegistry.lookup(key) do
      {:ok, mod}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec set(pid, key, value) :: :ok | {:error, :already_registered}
  def set(_pid, key, value) do
    case MiniBus.ServiceRegistry.register(key, :erlang.get(:name)) do
      {:ok, _pid} ->
        MiniBus.EventStream.emit({:update, @name, key}, value)
        :ok

      {:error, {:already_registered, _pid}} ->
        {:error, :already_registered}
    end
  end

  @spec del(pid, binary) :: :ok | {:error, :not_allowed | :not_found}
  def del(_pid, key) do
    MiniBus.ServiceRegistry.unregister(key)
  end

  @spec keys(pid) :: {:ok, [key]}
  def keys(_pid) do
    res =
      for item <- MiniBus.ServiceRegistry.keys() do
        {:protected, item}
      end

    {:ok, res}
  end

  def request(_pid, "names", _value) do
    list = MiniBus.ServiceRegistry.names()
    {:ok, list}
  end

  @spec request(pid, key, value) :: {:error, :not_found}
  def request(_pid, _key, _value) do
    {:error, :not_found}
  end
end
