defmodule MiniBus.MixProject do
  use Mix.Project

  def project do
    [
      app: :mini_bus,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MiniBus.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:monad_cps, "~> 0.1.0"},
      {:typed_struct, "~> 0.1.4"}
    ]
  end
end
