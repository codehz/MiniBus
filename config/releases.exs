import Config

with {:ok, port} <- System.fetch_env("LISTEN_PORT") do
  config :mini_bus, listen: {Integer.parse(port), []}
else
  :error ->
    with {:ok, path} <- System.fetch_env("LISTEN_UNIX") do
      config :mini_bus, listen: {0, [ifaddr: {:local, path}]}
    else
      :error ->
        config :mini_bus, listen: {4040, []}
        IO.warn("LISTEN_PORT or LISTEN_UNIX not set, use default port 4040")
    end
end
