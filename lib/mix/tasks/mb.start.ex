defmodule Mix.Tasks.Mb.Start do
  use Mix.Task
  @shortdoc "Start Message Blaster producer (direct SQS mode)"

  def run(args) do
    {opts, _rest, _} = OptionParser.parse(args, strict: [rate: :integer])

    Mix.Task.run("app.start")

    :ok = ensure_producer_started()

    rate = Keyword.get(opts, :rate)

    case rate do
      nil -> MessageBlaster.Producer.start_producing()
      r when is_integer(r) and r > 0 -> MessageBlaster.Producer.start_producing(rate: r)
      _ -> MessageBlaster.Producer.start_producing()
    end

    IO.puts("Producer started. Press Ctrl+C to stop.")
    Process.sleep(:infinity)
  end

  defp ensure_producer_started do
    case Process.whereis(MessageBlaster.Producer) do
      nil ->
        case MessageBlaster.Producer.start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          other -> other
        end
      _ -> :ok
    end
  end
end
