defmodule MiniBus.EventStream do
  @type key :: {:observe, String.t(), String.t()} | {:listen, String.t(), String.t()}
  @typep entry :: {pid, :ok}
  @typep entries :: [entry]

  @spec child_spec([
          {:listeners, [atom]}
          | {:meta, [{any, any}]}
          | {:name, atom}
          | {:partitions, pos_integer}
        ]) :: %{id: any, start: {Registry, :start_link, [[any], ...]}, type: :supervisor}
  def child_spec(options),
    do: Registry.child_spec([{:name, __MODULE__}, {:keys, :duplicate} | options])

  @spec listen(key, any) :: {:error, {:already_registered, pid}} | {:ok, pid}
  def listen(key, tag \\ nil) do
    Registry.register(__MODULE__, key, (if is_nil(tag), do: key, else: tag))
  end

  @spec emit({:update | :notify, String.t(), String.t()}, binary) :: :ok
  def emit({flag, service, key}, value) when flag == :update or flag == :notify do
    Registry.dispatch(__MODULE__, {target_flag(flag), service, key}, &dispatch({flag, value}, &1))
  end

  defp target_flag(:update), do: :observe
  defp target_flag(:notify), do: :listen

  @spec dispatch({:update | :notify, binary}, entries) :: :ok
  defp dispatch({flag, value}, entries) when flag == :update or flag == :notify do
    IO.inspect(entries, label: "dispatch")
    for {pid, tag} <- entries do
      send(pid, {:event, tag, value})
    end
    :ok
  end
end
