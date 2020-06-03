defmodule MiniBus.Utils.BitString do
  @spec __using__(any) ::
          {:__block__, [], [{:alias, [...], [...]} | {:require, [...], [...]}, ...]}
  defmacro __using__(_options) do
    quote do
      alias MiniBus.Utils.BitString
      require MiniBus.Utils.BitString
    end
  end

  defp gen_name(atom) do
    {:var!, [context: __MODULE__, import: Kernel], [{atom, [], __MODULE__}]}
  end

  defp gen_private_name(atom) do
    {atom, [], __MODULE__}
  end

  defp gen_binary_size(len) do
    {:-, [context: __MODULE__, import: Kernel], [{:binary, [], __MODULE__}, {:size, [], [len]}]}
  end

  defp gen_side(left, right) do
    {:"::", [], [left, right]}
  end

  defp gen({:short_binary, name}) when is_atom(name) do
    len = gen_private_name(:"#{name}-len")
    [gen_side(len, 8), gen_side(gen_name(name), gen_binary_size(len))]
  end

  defp gen({:binary, name}) when is_atom(name) do
    [gen_side(gen_name(name), gen_name(:binary))]
  end

  defp gen({:static, term}) do
    [term]
  end

  @spec debug(term()) :: {:<<>>, [], [term()]}
  def debug(list) do
    contents = list |> Enum.flat_map(&gen/1)

    {:<<>>, [], contents}
  end

  @spec match(term()) :: {:<<>>, [], [term()]}
  defmacro match(list) do
    debug(list)
  end
end
