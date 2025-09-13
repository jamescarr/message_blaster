defmodule Mix.Tasks.Mb.Rate do
  use Mix.Task
  @shortdoc "Adjust producer send rate at runtime"

  def run(args) do
    {opts, _rest, _} = OptionParser.parse(args, strict: [set: :integer])
    Mix.Task.run("app.start")

    case Process.whereis(MessageBlaster.Producer) do
      nil ->
        IO.puts("Producer not running. Start it with: mix mb.start --rate 20")
      _ ->
        case Keyword.get(opts, :set) do
          nil -> IO.puts("Usage: mix mb.rate --set <messages_per_second>")
          rate when is_integer(rate) and rate > 0 ->
            :ok = MessageBlaster.Producer.set_rate(rate)
            IO.puts("Rate updated to #{rate} msg/s")
          _ -> IO.puts("Invalid rate. Must be positive integer.")
        end
    end
  end
end
