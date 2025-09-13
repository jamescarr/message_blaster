defmodule Mix.Tasks.Mb.Sqs.Create do
  use Mix.Task
  @shortdoc "Create SQS queue for Message Blaster (LocalStack)"

  def run(_args) do
    Mix.Task.run("app.start")

    cfg = Application.get_env(:message_blaster, :sqs, [])
    queue_url = Keyword.get(cfg, :queue_url)
    region = Keyword.get(cfg, :region, "us-east-1")
    endpoint = Keyword.get(cfg, :endpoint)

    queue_name = queue_name_from_url(queue_url)

    exaws_cfg = [region: region]
    exaws_cfg =
      if endpoint do
        host = URI.parse(endpoint).host
        port = URI.parse(endpoint).port
        Keyword.put(exaws_cfg, :sqs, [scheme: "http://", host: host, port: port])
      else
        exaws_cfg
      end

    case ExAws.SQS.create_queue(queue_name) |> ExAws.request(exaws_cfg) do
      {:ok, _} -> IO.puts("Created queue: #{queue_name}")
      {:error, reason} -> IO.puts("Failed to create queue: #{inspect(reason)}")
    end
  end

  defp queue_name_from_url(nil), do: "message-blaster-events"
  defp queue_name_from_url(url) do
    url |> String.split("/") |> List.last()
  end
end
