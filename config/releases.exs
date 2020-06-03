import Config

with {:ok, port} <- System.fetch_env("PORT") do
  config :mini_bus, port: Integer.parse(port)
else
  :error ->
    IO.warn("PORT not set, use default 4040")
end
