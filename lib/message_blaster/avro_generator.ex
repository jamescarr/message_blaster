defmodule MessageBlaster.AvroGenerator do
  @moduledoc """
  Generates JSON maps that conform to a subset of Avro schemas:
  - primitives: string, int, long, double, boolean
  - enum
  - record (with nested fields)
  - arrays (of supported types)
  - maps (string keys -> supported types)
  - unions: will prefer the first non-null type
  """
  require Logger

  def generate(schema) when is_map(schema) do
    case schema_type(schema) do
      :record -> gen_record(schema)
      other ->
        Logger.warning("Top-level schema is not a record (#{inspect(other)}); generating scalar")
        gen_value(schema)
    end
  end

  defp schema_type(%{"type" => t}) when is_binary(t), do: normalize_type(t)
  defp schema_type(%{"type" => t}) when is_map(t), do: schema_type(t)
  defp schema_type(%{"type" => t}) when is_list(t), do: :union
  defp schema_type(t) when is_binary(t), do: normalize_type(t)
  defp schema_type(_), do: :unknown

  defp normalize_type("string"), do: :string
  defp normalize_type("int"), do: :int
  defp normalize_type("long"), do: :long
  defp normalize_type("double"), do: :double
  defp normalize_type("float"), do: :double
  defp normalize_type("boolean"), do: :boolean
  defp normalize_type("enum"), do: :enum
  defp normalize_type("record"), do: :record
  defp normalize_type("array"), do: :array
  defp normalize_type("map"), do: :map
  defp normalize_type(other) when is_binary(other), do: String.to_atom(other)

  defp gen_record(%{"fields" => fields} = _schema) when is_list(fields) do
    fields
    |> Enum.map(fn %{"name" => name} = f -> {name, gen_value(f)} end)
    |> Enum.into(%{})
  end

  defp gen_value(%{"type" => t} = field) when is_binary(t), do: gen_primitive(normalize_type(t), field)
  defp gen_value(%{"type" => %{"type" => t} = nested}), do: gen_primitive(normalize_type(t), nested)
  defp gen_value(%{"type" => types} = _field) when is_list(types) do
    # choose first non-null
    chosen = Enum.find(types, fn
      "null" -> false
      _ -> true
    end) || "null"
    gen_value(%{"type" => chosen})
  end
  defp gen_value(%{"symbols" => _} = enum_schema), do: gen_enum(enum_schema)
  defp gen_value(%{"type" => _} = schema), do: gen_value(schema["type"]) # recurse
  defp gen_value(t) when is_binary(t), do: gen_primitive(normalize_type(t), %{})
  defp gen_value(other) when is_map(other) do
    case schema_type(other) do
      :record -> gen_record(other)
      :enum -> gen_enum(other)
      :array -> gen_array(other)
      :map -> gen_map(other)
      typ -> gen_primitive(typ, other)
    end
  end

  defp gen_enum(%{"symbols" => symbols}) when is_list(symbols) and symbols != [] do
    Enum.random(symbols)
  end

  defp gen_array(%{"items" => items}) do
    len = Enum.random(0..3)
    for _ <- 1..len, do: gen_value(%{"type" => items})
  end

  defp gen_map(%{"values" => values}) do
    len = Enum.random(0..3)
    1..len
    |> Enum.map(fn _ -> {random_string(5), gen_value(%{"type" => values})} end)
    |> Enum.into(%{})
  end

  defp gen_primitive(:string, _f), do: random_string(Enum.random(5..12))
  defp gen_primitive(:int, _f), do: Enum.random(0..10_000)
  defp gen_primitive(:long, _f), do: Enum.random(0..1_000_000)
  defp gen_primitive(:double, _f), do: Float.round(:rand.uniform() * 10_000, 2)
  defp gen_primitive(:boolean, _f), do: Enum.random([true, false])
  defp gen_primitive(:enum, %{"symbols" => symbols}) when is_list(symbols), do: Enum.random(symbols)
  defp gen_primitive(:record, schema), do: gen_record(schema)
  defp gen_primitive(:array, schema), do: gen_array(schema)
  defp gen_primitive(:map, schema), do: gen_map(schema)
  defp gen_primitive(_, _), do: nil

  defp random_string(n) do
    for _ <- 1..n, into: "" do
      <<Enum.random('abcdefghijklmnopqrstuvwxyz')>>
    end
  end
end
