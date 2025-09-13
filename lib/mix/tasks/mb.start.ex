defmodule Mix.Tasks.Mb.Start do
  use Mix.Task
  @shortdoc "Start Message Blaster producer (direct SQS mode) with schema-based generation"

  alias MessageBlaster.{SchemaLoader, SchemaRegistryClient}

  @impl true
  def run(args) do
    {opts, _rest, _} = OptionParser.parse(args,
      strict: [rate: :integer, schema_dir: :string, schemas: :string]
    )

    Mix.Task.run("app.start")

    rate = opts[:rate] || env_int("RATE") || 50
    schema_dir = opts[:schema_dir] || System.get_env("SCHEMA_DIR") || schemas_path()
    pattern_csv = opts[:schemas] || System.get_env("SCHEMAS")

    :ok = ensure_producer_started()

    name_to_schema = SchemaLoader.load_all(schema_dir)
    selected = select_schemas(name_to_schema, pattern_csv)

    # Optionally register if registry is configured
    SchemaRegistryClient.register_all(selected)

    MessageBlaster.Producer.start_producing(rate: rate, schemas: selected)

    IO.puts("Producer started. RATE=#{rate} msg/s per schema; schemas=#{Enum.join(Map.keys(selected), ", ")}")
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

  defp schemas_path do
    Application.get_env(:message_blaster, :schemas, []) |> Keyword.get(:path, "./schemas")
  end

  defp env_int(name) do
    with val when is_binary(val) <- System.get_env(name),
         {num, _} <- Integer.parse(val) do
      num
    else
      _ -> nil
    end
  end

  defp select_schemas(name_to_schema, nil), do: name_to_schema
  defp select_schemas(name_to_schema, patterns_csv) do
    patterns =
      patterns_csv
      |> String.split([","], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    name_to_schema
    |> Enum.filter(fn {schema_name, _schema} -> matches_any?(schema_name, patterns) end)
    |> Enum.into(%{})
  end

  defp matches_any?(_schema_name, []), do: true
  defp matches_any?(schema_name, patterns) do
    Enum.any?(patterns, fn pat -> wildcard_match?(schema_name, pat) end)
  end

  defp wildcard_match?(name, pattern) do
    # Convert wildcard * to regex .*
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> then(&("^" <> &1 <> "$"))
      |> Regex.compile!()

    Regex.match?(regex, name)
  end
end
