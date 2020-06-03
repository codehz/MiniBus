defmodule MiniBus.Application do
  @moduledoc false

  use Application

  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    children = [
      MiniBus.EventStream,
      MiniBus.Client.Supervisor,
      MiniBus.ServiceRegistry,
      MiniBus.Builtin.RegistryProxy,
      MiniBus.Builtin.Shared,
      MiniBus.Gateway.TaskSupervisor.get_spec(),
      {MiniBus.Gateway, 4040}
    ]

    opts = [strategy: :one_for_one, name: MiniBus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
