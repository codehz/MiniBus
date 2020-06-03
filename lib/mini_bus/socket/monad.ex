defmodule MiniBus.Socket.Monad do
  @moduledoc false

  @error :error
  @timeout :timeout
  @ok :ok
  @infinity :infinity
  @time_unit :millisecond

  use ContinuationMonad

  @spec __using__(any) :: {:__block__, [], [{:import, [...], [...]} | {:use, [...], [...]}, ...]}
  defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)
      use ContinuationMonad
    end
  end

  @spec calc_timeout(:infinity | integer) :: :infinity | integer
  def calc_timeout(@infinity), do: @infinity

  def calc_timeout(deadline) do
    deadline - System.monotonic_time(@time_unit)
  end

  @spec make_deadline(:infinity | integer) :: :infinity | integer
  def make_deadline(@infinity), do: @infinity

  def make_deadline(timeout) do
    System.monotonic_time(@time_unit) + timeout
  end

  defp _return(x) do
    fn _socket, buffer, _deadline -> {@ok, x, buffer} end
  end

  @spec return(any) :: {:cont, (any -> any)}
  def return(x) do
    ic(_return(x))
  end

  @spec fail(any) :: {:cont, (any -> any)}
  def fail(e) do
    fn _socket, _buffer, _deadline -> {@error, e} end |> ic
  end

  @spec get_socket :: {:cont, (any -> any)}
  def get_socket() do
    fn socket, buffer, _deadline -> {@ok, socket, buffer} end |> ic
  end

  @spec get_buffer :: {:cont, (any -> any)}
  def get_buffer() do
    fn _socket, buffer, _deadline -> {@ok, buffer, buffer} end |> ic
  end

  @spec put_buffer(any) :: {:cont, (any -> any)}
  def put_buffer(new_buffer) do
    fn _socket, buffer, _deadline -> {@ok, buffer, new_buffer} end |> ic
  end

  @spec get_deadline :: {:cont, (any -> any)}
  def get_deadline() do
    fn _socket, buffer, deadline -> {@ok, deadline, buffer} end |> ic
  end

  @spec get_timeout :: {:cont, (any -> any)}
  def get_timeout() do
    fn _socket, buffer, deadline -> {@ok, calc_timeout(deadline), buffer} end |> ic
  end

  @spec has_daedline :: {:cont, (any -> any)}
  def has_daedline() do
    fn _socket, buffer, deadline -> {@ok, deadline != @infinity, buffer} end |> ic
  end

  @spec wrap(any) :: {:cont, (any -> any)}
  def wrap(fun) do
    fn socket, buffer, deadline ->
      with {@ok, result, buffer} <- fun.(socket, buffer, deadline) do
        {@ok, result, buffer}
      else
        {@error, e, buffer} -> {@error, e, buffer}
        {@error, e} -> {@error, e, buffer}
      end
    end
    |> ic
  end

  defp _bind(s, f) do
    fn socket, buffer, deadline ->
      if deadline < System.monotonic_time(@time_unit) do
        {@error, @timeout, buffer}
      else
        case s.(socket, buffer, deadline) do
          {@ok, result, buffer} ->
            f.(result).(socket, buffer, deadline)

          {@error, e, buffer} ->
            {@error, e, buffer}

          {@error, e} ->
            {@error, e, buffer}
        end
      end
    end
  end

  defp ic(ma) do
    make_ic(&_bind/2).(ma)
  end

  @spec run({:cont, (any -> any)}, port, binary, :infinity | integer) :: {:ok, any, binary} | {:error, any, binary}
  def run(m, socket, buffer, deadline \\ @infinity) do
    make_run(&_return/1).(m).(socket, buffer, deadline)
  end
end
