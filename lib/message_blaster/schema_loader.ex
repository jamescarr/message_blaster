defmodule MessageBlaster.SchemaLoader do
  @moduledoc """
  Loads Avro schemas from a directory (\*.avsc) and returns them keyed by full name.
  Full name is `namespace.name` if namespace present, otherwise `name`.
  """
  require Logger

  @type schema_map :: map()

  @spec load_all() :: %{optional(String.t()) => schema_map}
  def load_all do
    path = Application.get_env(:message_blaster, :schemas, []) |> Keyword.get(:path, "./schemas")
    with {:ok, files} <- File.ls(path) do
      files
      |> Enum.filter(&String.ends_with?(&1, ".avsc"))
      |> Enum.reduce(%{}, fn file, acc ->
        full = Path.join(path, file)
        case File.read(full) do
          {:ok, contents} ->
            case Jason.decode(contents) do
              {:ok, schema} ->
                name = full_name(schema)
                Logger.debug("Loaded schema #{name} from #{file}")
                Map.put(acc, name, schema)
              {:error, reason} ->
                Logger.error("Failed to decode schema #{file}: #{inspect(reason)}")
                acc
            end
          {:error, reason} ->
            Logger.error("Failed to read schema #{file}: #{inspect(reason)}")
            acc
        end
      end)
    else
      {:error, :enoent} ->
        Logger.warning("Schemas path not found; skipping schema load")
        %{}
      {:error, reason} ->
        Logger.error("Failed to list schemas: #{inspect(reason)}")
        %{}
    end
  end

  @spec full_name(map()) :: String.t()
  def full_name(%{"name" => name, "namespace" => ns}) when is_binary(name) and is_binary(ns), do: ns <> "." <> name
  def full_name(%{"name" => name}) when is_binary(name), do: name
  def full_name(_), do: "unknown"
end
