defmodule MiniBus.ServiceRegistry do
  @type key :: String.t()

  @spec child_spec([
          {:listeners, [atom]}
          | {:meta, [{any, any}]}
          | {:name, atom}
          | {:partitions, pos_integer}
        ]) :: %{id: any, start: {Registry, :start_link, [[any], ...]}, type: :supervisor}
  def child_spec(options),
    do: Registry.child_spec([{:name, __MODULE__}, {:keys, :unique} | options])

  @spec register(key(), module()) :: {:error, {:already_registered, pid}} | {:ok, pid}
  def register(key, value) do
    Registry.register(__MODULE__, key, value)
  end

  @spec unregister(key()) :: :ok | {:error, :not_found | :not_allowed}
  def unregister(key) do
    se = self()

    with [{^se, _}] <- Registry.lookup(__MODULE__, key) do
      Registry.unregister(__MODULE__, key)
      :ok
    else
      [] -> {:error, :not_found}
      _ -> {:error, :not_allowed}
    end
  end

  @spec lookup(key()) :: nil | {pid, module()}
  def lookup(key) do
    case Registry.lookup(__MODULE__, key) do
      [{pid, module}] ->
        {pid, module}

      [] ->
        nil
    end
  end

  @spec keys :: [key()]
  def keys() do
    Registry.select(__MODULE__, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @spec names :: [String.t()]
  def names() do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :_}, [{:==, :"$2", self()}], [:"$1"]}])
  end
end
