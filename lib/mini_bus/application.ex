defmodule MiniBus.Application do
  @moduledoc false

  use Application

  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    port = Application.fetch_env!(:mini_bus, :port)

    children =
      [
        MiniBus.EventStream,
        MiniBus.Client.Supervisor,
        MiniBus.ServiceRegistry,
        MiniBus.Builtin.RegistryProxy,
        MiniBus.Builtin.Shared,
        MiniBus.Gateway.TaskSupervisor.get_spec(),
        {MiniBus.Gateway, port}
      ] ++ http_server()

    opts = [strategy: :one_for_one, name: MiniBus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp http_server() do
    with {:ok, opts} <- Application.fetch_env(:mini_bus, :http) do
      if nil == opts do
        []
      else
        [{Plug.Cowboy, scheme: :http, plug: MiniBus.WebGateway, options: opts}]
      end
    else
      _ -> []
    end
  end
end
