defmodule MiniBus.Client.Supervisor do
  use DynamicSupervisor

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec create_client(port) :: :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def create_client(socket) do
    DynamicSupervisor.start_child(__MODULE__, %{
      id: __MODULE__,
      start: {MiniBus.Client, :start_link, [socket]},
      restart: :temporary
    })
  end

  @spec init(:ok) ::
          {:ok,
           %{
             extra_arguments: [any],
             intensity: non_neg_integer,
             max_children: :infinity | non_neg_integer,
             period: pos_integer,
             strategy: :one_for_one
           }}
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
