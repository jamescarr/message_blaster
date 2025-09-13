defmodule MessageBlaster.SchemaRegistryClient do
  @moduledoc """
  Minimal Confluent Schema Registry client for registering Avro schemas.
  Only supports register subject version: POST /subjects/<subject>/versions
  """
  require Logger

  @headers [
    {"content-type", "application/vnd.schemaregistry.v1+json"}
  ]

  @spec register_all(%{optional(String.t()) => map()}, keyword()) :: :ok
  def register_all(name_to_schema, opts \\ []) when is_map(name_to_schema) do
    url = registry_url()
    if is_nil(url) do
      Logger.info("SCHEMA_REGISTRY_URL not set; skipping schema registration")
      :ok
    else
      subject_fn = Keyword.get(opts, :subject_fn, &default_subject/1)
      Enum.each(name_to_schema, fn {full_name, schema} ->
        subject = subject_fn.(full_name)
        body = %{"schema" => Jason.encode!(schema)} |> Jason.encode!()
        endpoint = url <> "/subjects/" <> subject <> "/versions"
        case :hackney.request(:post, endpoint, @headers, body, []) do
          {:ok, status, _resp_headers, client} when status in 200..299 ->
            {:ok, resp_body} = :hackney.body(client)
            Logger.info("Registered schema #{subject}: #{resp_body}")
          {:ok, status, _h, client} ->
            {:ok, resp_body} = :hackney.body(client)
            Logger.error("Failed to register #{subject} (#{status}): #{resp_body}")
          {:error, reason} ->
            Logger.error("HTTP error registering #{subject}: #{inspect(reason)}")
        end
      end)
      :ok
    end
  end

  defp default_subject(full_name), do: full_name <> "-value"

  defp registry_url do
    System.get_env("SCHEMA_REGISTRY_URL")
  end
end
