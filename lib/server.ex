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

    {:ok, listen_socket} = :gen_tcp.listen(6379, [:binary, active: false, reuseaddr: true])
    loop_accept(listen_socket)
  end

  def loop_accept(listen_socket) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)

    spawn(fn ->
      handle_receive(socket)
    end)

    loop_accept(listen_socket)
  end

  def handle_receive(socket) do
    received_data = :gen_tcp.recv(socket, 0)
    IO.inspect(received_data, label: :received_data)

    case received_data do
      {:ok, _data} ->
        :gen_tcp.send(socket, "+PONG\r\n")
        handle_receive(socket)

      {:error, :closed} ->
        :gen_tcp.close(socket)
    end
  end
end
