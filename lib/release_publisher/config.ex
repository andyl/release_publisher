defmodule ReleasePublisher.Config do
  @moduledoc """
  Loads and validates `config/release_publisher.yml`.

  Returns a list of publisher entry maps, in declared order. Missing
  file, empty file, or missing `publish:` all return `{:ok, []}` —
  those are valid "nothing configured" states, not errors.

  Validation is strict. Unknown keys at the publisher level are an
  error, not silently ignored: a typo like `prerelease:` spelled
  `preelease:` should fail loudly rather than publish the wrong thing.
  """

  alias ReleasePublisher.{Error, Publisher}

  @default_path "config/release_publisher.yml"

  @allowed_keys %{
    "github" => ["type", "draft", "prerelease"],
    "file" => ["type", "path"]
  }

  @required_keys %{
    "github" => [],
    "file" => ["path"]
  }

  @doc """
  Load the config from the default path.
  """
  @spec load() :: {:ok, [map()]} | {:error, Error.t()}
  def load, do: load(@default_path)

  @doc """
  Load the config from a specific path.
  """
  @spec load(Path.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def load(path) do
    cond do
      not File.exists?(path) ->
        {:ok, []}

      true ->
        case File.read!(path) |> parse_yaml(path) do
          {:ok, nil} -> {:ok, []}
          {:ok, %{} = doc} -> normalize(doc, path)
          {:ok, _} -> malformed_error(path, "top level must be a map")
          {:error, err} -> {:error, err}
        end
    end
  end

  # --- parsing ---------------------------------------------------------

  defp parse_yaml(content, path) do
    case YamlElixir.read_from_string(content) do
      {:ok, doc} ->
        {:ok, doc}

      {:error, %{__struct__: _} = err} ->
        {:error,
         Error.new(
           publisher: "release_publisher",
           step: "config",
           message: "could not parse #{path}: #{Exception.message(err)}",
           fix: "fix the YAML syntax in #{path}"
         )}

      {:error, other} ->
        {:error,
         Error.new(
           publisher: "release_publisher",
           step: "config",
           message: "could not parse #{path}: #{inspect(other)}",
           fix: "fix the YAML syntax in #{path}"
         )}
    end
  end

  defp normalize(doc, path) do
    case Map.get(doc, "publish") do
      nil ->
        {:ok, []}

      [] ->
        {:ok, []}

      list when is_list(list) ->
        validate_entries(list, path)

      _ ->
        malformed_error(path, "`publish:` must be a list")
    end
  end

  defp validate_entries(entries, path) do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {entry, idx}, {:ok, acc} ->
      case validate_entry(entry, idx, path) do
        {:ok, valid} -> {:cont, {:ok, [valid | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      other -> other
    end
  end

  defp validate_entry(entry, idx, path) when is_map(entry) do
    with {:ok, type} <- fetch_type(entry, idx, path),
         :ok <- check_known_type(type, idx, path),
         :ok <- check_allowed_keys(entry, type, idx, path),
         :ok <- check_required_keys(entry, type, idx, path) do
      {:ok, entry}
    end
  end

  defp validate_entry(_, idx, path),
    do: malformed_error(path, "publish[#{idx}] must be a map")

  defp fetch_type(entry, idx, path) do
    case Map.get(entry, "type") do
      type when is_binary(type) -> {:ok, type}
      _ -> malformed_error(path, "publish[#{idx}] is missing required key `type`")
    end
  end

  defp check_known_type(type, idx, path) do
    if type in Map.keys(@allowed_keys) do
      :ok
    else
      known = Enum.join(Publisher.known_types(), ", ")
      malformed_error(path, "publish[#{idx}] has unknown type #{inspect(type)} (known: #{known})")
    end
  end

  defp check_allowed_keys(entry, type, idx, path) do
    allowed = Map.fetch!(@allowed_keys, type)
    extras = Map.keys(entry) -- allowed

    case extras do
      [] ->
        :ok

      _ ->
        malformed_error(
          path,
          "publish[#{idx}] (#{type}) has unknown keys: #{inspect(extras)}"
        )
    end
  end

  defp check_required_keys(entry, type, idx, path) do
    required = Map.fetch!(@required_keys, type)
    missing = required -- Map.keys(entry)

    case missing do
      [] ->
        :ok

      _ ->
        malformed_error(
          path,
          "publish[#{idx}] (#{type}) is missing required keys: #{inspect(missing)}"
        )
    end
  end

  defp malformed_error(path, message) do
    {:error,
     Error.new(
       publisher: "release_publisher",
       step: "config",
       message: "#{path}: #{message}",
       fix: "see README.md for the config shape"
     )}
  end
end
