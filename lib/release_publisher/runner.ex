defmodule ReleasePublisher.Runner do
  @moduledoc """
  Orchestrates a publish run.

  Steps, in order:

    1. Filter the configured publishers by `--only` (list of type
       strings). An empty `--only` means "everything".
    2. Inject runtime keys (`:app`, `:version`, `:replace`, `:dry_run`,
       `:cmd_fun`) into each entry.
    3. **Global preflight pass**: run every publisher's `preflight/1`
       first. Abort the whole run if any fail — no partial state from
       typo'd config.
    4. Unless `--dry-run`, run each publisher's `publish/4` in declared
       order. Stop on first error. No cross-publisher rollback.

  All output is printed via `Mix.shell().info/1` / `Mix.shell().error/1`
  so tests can capture it.
  """

  alias ReleasePublisher.{Error, Publisher, Tarball}

  @type options :: %{
          required(:replace) => boolean(),
          required(:dry_run) => boolean(),
          required(:only) => [String.t()],
          optional(:cmd_fun) => (String.t(), [String.t()], keyword() -> {binary(), integer()})
        }

  @doc """
  Run the publish pipeline.

  Returns `:ok` on success or `{:error, %ReleasePublisher.Error{}}` on
  the first failure.
  """
  @spec run([map()], options(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def run(entries, opts, app, version) do
    only = Map.get(opts, :only, [])
    filtered = filter_by_only(entries, only)

    cond do
      entries == [] ->
        Mix.shell().info("release_publisher: nothing configured — exiting")
        :ok

      filtered == [] and only != [] ->
        Mix.shell().info(
          "release_publisher: no publishers matched --only #{Enum.join(only, ",")}"
        )

        :ok

      true ->
        entries = Enum.map(filtered, &inject_runtime(&1, opts, app, version))
        tarball = Tarball.expected_path(app, version)

        with :ok <- global_preflight(entries) do
          if Map.get(opts, :dry_run, false) do
            Enum.each(entries, fn entry ->
              Mix.shell().info(
                "release_publisher: [dry-run] would publish via #{Publisher.identity(entry)}"
              )
            end)

            :ok
          else
            publish_all(entries, tarball, app, version)
          end
        end
    end
  end

  # --- filtering -------------------------------------------------------

  defp filter_by_only(entries, []), do: entries

  defp filter_by_only(entries, only) do
    Enum.filter(entries, fn %{"type" => type} -> type in only end)
  end

  # --- runtime key injection ------------------------------------------

  defp inject_runtime(entry, opts, app, version) do
    Map.merge(entry, %{
      :app => app,
      :version => version,
      :replace => Map.get(opts, :replace, false),
      :dry_run => Map.get(opts, :dry_run, false),
      :cmd_fun => Map.get(opts, :cmd_fun, &System.cmd/3)
    })
  end

  # --- preflight -------------------------------------------------------

  defp global_preflight(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case dispatch_preflight(entry) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp dispatch_preflight(entry) do
    case Publisher.dispatch(entry) do
      {:ok, module} -> module.preflight(entry)
      {:error, _} = err -> err
    end
  end

  # --- publishing ------------------------------------------------------

  defp publish_all(entries, tarball, app, version) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      identity = Publisher.identity(entry)

      case Publisher.dispatch(entry) do
        {:ok, module} ->
          case module.publish(entry, tarball, app, version) do
            :ok ->
              Mix.shell().info("release_publisher: #{identity} ok")
              {:cont, :ok}

            {:error, _} = err ->
              Mix.shell().error("release_publisher: #{identity} failed")
              {:halt, err}
          end

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end
end
