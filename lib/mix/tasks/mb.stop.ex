defmodule Mix.Tasks.Mb.Stop do
  use Mix.Task
  @shortdoc "Stop Message Blaster producer"

  def run(_args) do
    Mix.Task.run("app.start")
    case Process.whereis(MessageBlaster.Producer) do
      nil -> IO.puts("Producer not running")
      _ -> MessageBlaster.Producer.stop_producing()
    end
  end
end
