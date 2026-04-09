defmodule Mix.Tasks.Release.Publish do
  @shortdoc "Publishes an already-built release tarball to configured targets"

  @moduledoc """
  Publishes the pre-built release tarball to one or more configured
  publishers.

  This task does not build, fetch, or deploy — it only publishes a
  tarball that `mix release` has already produced. The publishers are
  declared in `config/release_publisher.yml` (a stable public contract
  that downstream deploy tools can read).

  ## Flags

    * `--init`     — write a starter `config/release_publisher.yml` and exit.
    * `--replace`  — if an artifact already exists at a target, delete and recreate it.
    * `--only`     — run only publishers of the given type. Repeatable,
      or comma-separated (`--only github,file`).
    * `--dry-run`  — run preflight and report what would be published.

  ## Preflight

  Before any upload begins, every publisher's preflight checks run
  **globally**. If any publisher's preflight fails, the whole run aborts
  before a single byte has been uploaded.

  ## Error output

  Every user-correctable error is printed as three lines —
  publisher / step / minimal fix — via `ReleasePublisher.Error.format/1`.
  No stack traces for user-correctable errors.
  """

  use Mix.Task

  alias ReleasePublisher.{Config, Error, Init, Runner, Tarball}

  @switches [
    init: :boolean,
    replace: :boolean,
    only: :keep,
    dry_run: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      Keyword.get(opts, :init, false) ->
        run_init()

      true ->
        run_publish(opts)
    end
  end

  # --- --init ----------------------------------------------------------

  defp run_init do
    case Init.run() do
      {:ok, path} ->
        Mix.shell().info("release_publisher: wrote #{path}")
        :ok

      {:error, %Error{} = err} ->
        abort(err)
    end
  end

  # --- publish ---------------------------------------------------------

  defp run_publish(opts) do
    replace? = Keyword.get(opts, :replace, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    only = parse_only(opts)

    with {:ok, entries} <- Config.load(),
         {:ok, app, version} <- project_app_and_version(),
         :ok <- check_single_release(),
         :ok <- check_tarball_present(app, version, entries) do
      run_opts = %{replace: replace?, dry_run: dry_run?, only: only}

      case Runner.run(entries, run_opts, app, version) do
        :ok -> :ok
        {:error, %Error{} = err} -> abort(err)
      end
    else
      {:error, %Error{} = err} -> abort(err)
    end
  end

  defp parse_only(opts) do
    opts
    |> Keyword.get_values(:only)
    |> Enum.flat_map(&String.split(&1, ",", trim: true))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp project_app_and_version do
    config = Mix.Project.config()

    case {config[:app], config[:version]} do
      {nil, _} ->
        {:error,
         Error.new(
           publisher: "release_publisher",
           step: "mix-project",
           message: "could not read :app from Mix.Project.config()",
           fix: "ensure you are running inside a Mix project"
         )}

      {_, nil} ->
        {:error,
         Error.new(
           publisher: "release_publisher",
           step: "mix-project",
           message: "could not read :version from Mix.Project.config()",
           fix: "set @version in mix.exs"
         )}

      {app, version} ->
        {:ok, to_string(app), to_string(version)}
    end
  end

  defp check_single_release do
    case Mix.Project.config()[:releases] do
      nil ->
        :ok

      releases when is_list(releases) and length(releases) > 1 ->
        {:error,
         Error.new(
           publisher: "release_publisher",
           step: "mix-project",
           message: "multiple releases defined in mix.exs",
           fix: "v1 supports one release per project; pick one in releases/0"
         )}

      _ ->
        :ok
    end
  end

  defp check_tarball_present(_app, _version, []), do: :ok

  defp check_tarball_present(app, version, _entries) do
    Tarball.verify(app, version)
  end

  # --- error handling --------------------------------------------------

  defp abort(%Error{} = err) do
    Mix.shell().error(Error.format(err))
    Mix.raise("release_publisher failed")
  end
end
