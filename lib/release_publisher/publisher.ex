defmodule ReleasePublisher.Publisher do
  @moduledoc """
  Behaviour implemented by each publisher (github, file, …) plus the
  single type → module dispatch map.

  Adding a new publisher type is additive: implement the behaviour in a
  new module under `ReleasePublisher.Publishers.*` and add one line to
  `dispatch/1`. Nothing else in the pipeline needs to change.

  ## Entry map

  The `entry` passed to `c:preflight/1` and `c:publish/4` is the raw
  YAML map for this publisher (e.g.
  `%{"type" => "github", "draft" => false}`) with a few runtime keys
  added by the runner:

    * `:app`      — app name string (from `Mix.Project.config()`)
    * `:version`  — version string (from `Mix.Project.config()`)
    * `:replace`  — boolean, `--replace` flag state
    * `:dry_run`  — boolean, `--dry-run` flag state
    * `:cmd_fun`  — 3-arity command runner (test injection hook;
      defaults to `&System.cmd/3`)
  """

  alias ReleasePublisher.Error

  @type entry :: map()

  @callback preflight(entry()) :: :ok | {:error, Error.t()}

  @callback publish(
              entry(),
              tarball :: Path.t(),
              app :: String.t(),
              version :: String.t()
            ) :: :ok | {:error, Error.t()}

  @dispatch %{
    "github" => ReleasePublisher.Publishers.Github,
    "file" => ReleasePublisher.Publishers.File
  }

  @doc """
  All known publisher type strings.
  """
  @spec known_types() :: [String.t()]
  def known_types, do: Map.keys(@dispatch)

  @doc """
  Resolve a type string (or an entry map with `"type"`) to its
  implementing module.
  """
  @spec dispatch(String.t() | map()) :: {:ok, module()} | {:error, Error.t()}
  def dispatch(%{"type" => type}), do: dispatch(type)

  def dispatch(type) when is_binary(type) do
    case Map.fetch(@dispatch, type) do
      {:ok, mod} ->
        {:ok, mod}

      :error ->
        {:error,
         Error.new(
           publisher: "release_publisher",
           step: "config",
           message: "unknown publisher type: #{inspect(type)}",
           fix: "use one of: #{Enum.join(known_types(), ", ")}"
         )}
    end
  end

  @doc """
  A short human-readable identity for a publisher entry, used in error
  messages and per-publisher status lines.

      iex> ReleasePublisher.Publisher.identity(%{"type" => "github"})
      "github"

      iex> ReleasePublisher.Publisher.identity(%{"type" => "file", "path" => "/tmp/rel"})
      "file[/tmp/rel]"
  """
  @spec identity(map()) :: String.t()
  def identity(%{"type" => "file", "path" => path}) when is_binary(path), do: "file[#{path}]"
  def identity(%{"type" => type}) when is_binary(type), do: type
  def identity(_), do: "unknown"
end
