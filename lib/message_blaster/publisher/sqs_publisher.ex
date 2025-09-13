defmodule MessageBlaster.Publisher.SQSPublisher do
  @moduledoc """
  Minimal SQS publisher for direct mode.
  """
  require Logger

  def send_message(body) when is_binary(body) do
    %{"queue_url" => queue_url, "region" => region, "endpoint" => endpoint} = sqs_config()

    # Configure ExAws per-request to support custom endpoints
    exaws_cfg = [region: region]
    exaws_cfg =
      if endpoint do
        Keyword.put(exaws_cfg, :sqs, [scheme: "http://", host: URI.parse(endpoint).host, port: URI.parse(endpoint).port])
      else
        exaws_cfg
      end

    request = ExAws.SQS.send_message(queue_url, body)

    case ExAws.request(request, exaws_cfg) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error("Failed to publish to SQS: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sqs_config do
    cfg = Application.get_env(:message_blaster, :sqs, [])
    %{
      "queue_url" => Keyword.get(cfg, :queue_url),
      "endpoint" => Keyword.get(cfg, :endpoint),
      "region" => Keyword.get(cfg, :region, "us-east-1")
    }
  end
end
