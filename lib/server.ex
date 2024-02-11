defmodule Server do
  @moduledoc """
  Custom implementation of a Redis server
  """

  use Application

  def start(_type, _args) do
    Supervisor.start_link([{Task, fn -> Server.listen() end}], strategy: :one_for_one)
  end

  @doc """
  Listen for incoming connections
  """
  def listen() do
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    IO.puts("Logs from your program will appear here!")

    {:ok, socket} = :gen_tcp.listen(6379, [:binary, active: false, reuseaddr: true])
    {:ok, client} = :gen_tcp.accept(socket)
    loop(client)
  end

  def loop(client) do
    recv_data = :gen_tcp.recv(client, 0)    # Read the incoming data
    IO.puts("recv data: #{inspect(recv_data)}")
    case recv_data do
      {:ok, _data} ->
        :gen_tcp.send(client, "+PONG\r\n")         # Send the PONG response
        loop(client)                               # Continue the loop
      {:error, :closed} ->
        :gen_tcp.close(client)
    end
  end
end
