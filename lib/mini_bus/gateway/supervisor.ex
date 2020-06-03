defmodule MiniBus.Gateway.TaskSupervisor do
  @spec get_spec :: {Task.Supervisor, [{:name, MiniBus.Gateway.TaskSupervisor}, ...]}
  def get_spec(),
    do: {Task.Supervisor, name: __MODULE__}

  @spec start_child((() -> any)) :: :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def start_child(func) do
    Task.Supervisor.start_child(__MODULE__, func)
  end
end
