defmodule Server do
  @moduledoc """
  Custom implementation of a Redis server
  """
  alias Server.MemoryStore

  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Task, fn -> Server.listen() end},
        MemoryStore
      ],
      strategy: :one_for_one
    )
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

  defp loop_accept(listen_socket) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)

    spawn(fn ->
      handle_receive(socket)
    end)

    loop_accept(listen_socket)
  end

  defp handle_receive(socket) do
    received_data = :gen_tcp.recv(socket, 0)
    IO.inspect(received_data, label: :received_data)

    case received_data do
      {:ok, data} ->
        [cmd | args] = parse_data(data)
        IO.inspect([cmd | args], label: :parsed_data)

        case String.downcase(cmd) do
          "ping" ->
            reply = if Enum.empty?(args), do: simple_string("PONG"), else: bulk_string(args)
            :gen_tcp.send(socket, reply |> IO.inspect(label: :reply))

          "echo" ->
            reply = bulk_string(args)
            :gen_tcp.send(socket, reply |> IO.inspect(label: :reply))

          "set" ->
            [key, value] = args
            previous_value = MemoryStore.get(key)
            MemoryStore.set(key, value)

            reply =
              if is_nil(previous_value),
                do: simple_string("OK"),
                else: bulk_string(previous_value)

            :gen_tcp.send(socket, reply |> IO.inspect(label: :reply))

          "get" ->
            key = args |> List.first()
            reply = MemoryStore.get(key) |> bulk_string()
            :gen_tcp.send(socket, reply |> IO.inspect(label: :reply))
        end

        handle_receive(socket)

      {:error, :closed} ->
        :gen_tcp.close(socket)
    end
  end

  defp simple_string(value), do: "+#{value}\r\n"

  defp bulk_string(value) when is_nil(value), do: "$-1\r\n"

  defp bulk_string(value) when is_binary(value) do
    "$#{String.length(value)}\r\n#{value}\r\n"
  end

  # [] => $0\r\n\r\n
  # ["hello"] => $5\r\nhello\r\n
  # ["hello world"] => *2\r\n$5\r\nhello\r\n$5\r\nworld\r\n
  defp bulk_string(values) when is_list(values) do
    case Enum.count(values) do
      0 ->
        "$0\r\n\r\n"

      1 ->
        value = values |> List.first()
        "$#{String.length(value)}\r\n#{value}\r\n"

      count ->
        initial = "*#{count}\r\n"

        Enum.reduce(values, initial, fn value, acc ->
          "#{acc}$#{String.length(value)}\r\n#{value}\r\n"
        end)
    end
  end

  # "*1\r\n$4\r\nping\r\n" => ["ping"]
  # "*2\r\n$4\r\necho\r\n$3\r\nhey\r\n" => ["echo", "hey"]
  # "*4\r\n$4\r\necho\r\n$4\r\nthis\r\n$2\r\nis\r\n$7\r\nsparta!\r\n" => ["echo", "this", "is", "sparta!"]
  defp parse_data(data) do
    case data do
      "*" <> rest -> parse_array(rest)
      "$" <> rest -> parse_bulk_string(rest)
      _ -> raise "Not implemented error. data: #{inspect(data)}"
    end
  end

  defp parse_array(data) do
    {:ok, size_str, rest} = until_crlf(data)
    {size, _} = Integer.parse(size_str)

    {values, _rest} =
      Enum.reduce_while(1..size, {[], rest}, fn counter, acc ->
        if counter <= size do
          {parsed, data} = acc
          [parsed_chunk, data_rest] = parse_data(data)

          {:cont, {[parsed_chunk | parsed], data_rest}}
        else
          {:halt, acc}
        end
      end)

    values
    |> Enum.reverse()
  end

  defp parse_bulk_string(data) do
    {:ok, _size_str, rest} = until_crlf(data)

    {:ok, string, rest} = until_crlf(rest)
    [string, rest]
  end

  @crlf "\r\n"

  defp until_crlf(data, acc \\ "")

  defp until_crlf(<<@crlf, rest::binary>>, acc), do: {:ok, acc, rest}
  defp until_crlf(<<byte, rest::binary>>, acc), do: until_crlf(rest, <<acc::binary, byte>>)

  defmodule MemoryStore do
    use Agent

    def start_link(_opts) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def get(key) do
      Agent.get(__MODULE__, &Map.get(&1, key))
    end

    def set(key, value) do
      Agent.update(__MODULE__, &Map.put(&1, key, value))
    end
  end
end
