defmodule MiniBus.Gateway do
  use GenServer

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  @doc """
  Starts the gateway
  """
  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl GenServer
  @spec init(char) :: {:ok, port, {:continue, :ok}}
  def init(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, socket, {:continue, :ok}}
  end

  @impl GenServer
  @spec handle_continue(:ok, port) :: {:noreply, port, {:continue, :ok}}
  def handle_continue(:ok, socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, _} = MiniBus.Gateway.TaskSupervisor.start_child(fn -> handle_child(client) end)
    {:noreply, socket, {:continue, :ok}}
  end

  defp handle_child(client) do
    import MiniBus.Socket.HandshakeParser

    with {:ok, _, _} <- parse(client, 1000) do
      MiniBus.Client.Supervisor.create_client(client)
    else
      _ -> :gen_tcp.close(client)
    end
  end
end
