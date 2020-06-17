defmodule MiniBus.WebGateway do
  use Plug.Router

  plug(CORSPlug, methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"])
  plug(:match)
  plug(:dispatch)

  @spec service_command(String.t(), atom, [any]) :: any
  defp service_command(bucket, method, args) do
    with {pid, module} <- MiniBus.ServiceRegistry.lookup(bucket) do
      apply(module, method, [pid | args])
    else
      nil -> {:error, :bucket_not_found}
    end
  end

  defp as_resp({:error, :bucket_not_found}, conn), do: send_resp(conn, 404, "bucket_not_found")
  defp as_resp({:error, :not_found}, conn), do: send_resp(conn, 404, "not_found")
  defp as_resp({:error, :not_allowed}, conn), do: send_resp(conn, 403, "not_allowed")
  defp as_resp({:error, e}, conn), do: send_resp(conn, 500, e)

  defp as_resp({:ok, value}, conn) when is_list(value) do
    data =
      for [acl, name] <- value do
        case acl do
          :public -> ["+", name, 0]
          :protected -> ["-", name, 0]
          :private -> []
        end
      end

    send_resp(conn, 200, data)
  end

  defp as_resp({:ok, value}, conn), do: send_resp(conn, 200, value)
  defp as_resp(:ok, conn), do: send_resp(conn, 200, [])

  get "/ping" do
    send_resp(conn, 200, "pong")
  end

  match "/map/:bucket", via: :head do
    with {_pid, _module} <- MiniBus.ServiceRegistry.lookup(bucket) do
      send_resp(conn, 200, [])
    else
      nil -> send_resp(conn, 404, "")
    end
  end

  get "/map/:bucket" do
    conn = send_chunked(conn, 200)
    with {:ok, arr} <- service_command(bucket, :keys, []) do
      Enum.reduce_while(arr, conn, fn ({acl, name}, conn) ->
        item = case acl do
          :public -> ["+", name, 0]
          :protected -> ["-", name, 0]
          :private -> []
        end
        case chunk(conn, item) do
          {:ok, conn} ->
            {:cont, conn}

          {:error, :closed} ->
            {:halt, conn}
        end
      end)
    end
  end

  match "/map/:bucket/:key", via: :head do
    with {pid, module} <- MiniBus.ServiceRegistry.lookup(bucket),
         {:ok, _} <- apply(module, :get, [pid, key]) do
      send_resp(conn, 200, "")
    else
      nil -> send_resp(conn, 404, "")
      {:error, :not_allowed} -> send_resp(conn, 403, "")
      {:error, _} -> send_resp(conn, 404, "")
    end
  end

  get "/map/:bucket/:key" do
    service_command(bucket, :get, [key]) |> as_resp(conn)
  end

  put "/map/:bucket/:key" do
    {:ok, value, conn} = read_body(conn)

    service_command(bucket, :set, [key, value]) |> as_resp(conn)
  end

  delete "/map/:bucket/:key" do
    service_command(bucket, :del, [key]) |> as_resp(conn)
  end

  post "/map/:bucket/:key" do
    {:ok, value, conn} = read_body(conn)

    service_command(bucket, :request, [key, value]) |> as_resp(conn)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
