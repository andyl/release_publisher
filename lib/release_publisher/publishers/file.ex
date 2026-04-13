defmodule ReleasePublisher.Publishers.File do
  @moduledoc """
  Publishes a release tarball by copying it to a local or mounted
  filesystem path.

  Preflight:

    1. `path` is set.
    2. `~/` paths are expanded to the user's home directory.
       `~user/` forms are rejected.
    3. `path` is absolute (relative paths are explicitly rejected — a
       typo should never silently write into the current directory).
    4. `path` is auto-created if it does not exist. Must be writable.
    5. No file named `<app>-<version>.tar.gz` exists at `path` (unless
       `--replace`).
    6. Tarball exists at the conventional build path.

  `publish/4` uses `File.cp!/2`. `--replace` overwrites in place.
  """

  @behaviour ReleasePublisher.Publisher

  alias ReleasePublisher.{Error, Tarball}

  @impl true
  def preflight(entry) do
    with {:ok, path} <- check_path_set(entry),
         {:ok, path} <- expand_tilde(entry, path),
         :ok <- check_absolute(entry, path),
         :ok <- ensure_dir(entry, path),
         :ok <- check_dir_writable(entry, path),
         :ok <- check_no_collision(entry, path),
         :ok <- check_tarball(entry) do
      :ok
    end
  end

  @impl true
  def publish(entry, tarball, _app, _version) do
    dest = destination(entry, tarball)

    try do
      File.cp!(tarball, dest)
      :ok
    rescue
      e in File.CopyError ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "upload",
           message: "could not copy tarball: #{Exception.message(e)}",
           fix: "check that #{Path.dirname(dest)} is writable"
         )}
    end
  end

  # --- preflight steps -------------------------------------------------

  defp check_path_set(entry) do
    case Map.get(entry, "path") do
      nil ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:path",
           message: "file publisher is missing required `path:` key",
           fix: "add `path: /absolute/path/to/dir` to the publisher entry"
         )}

      "" ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:path",
           message: "file publisher `path:` is empty",
           fix: "set `path:` to an absolute directory"
         )}

      path when is_binary(path) ->
        {:ok, path}
    end
  end

  defp expand_tilde(_entry, "~/" <> rest) do
    {:ok, Path.expand("~/" <> rest)}
  end

  defp expand_tilde(entry, "~" <> _ = path) do
    {:error,
     Error.new(
       publisher: identity(entry),
       step: "preflight:path",
       message: "path #{inspect(path)} uses ~user syntax which is not supported",
       fix: "use ~/... (current user) or a fully absolute path"
     )}
  end

  defp expand_tilde(_entry, path), do: {:ok, path}

  defp check_absolute(entry, path) do
    if Path.type(path) == :absolute do
      :ok
    else
      {:error,
       Error.new(
         publisher: identity(entry),
         step: "preflight:path",
         message: "path #{inspect(path)} is not absolute",
         fix: "use an absolute path like `/mnt/releases/myapp/`"
       )}
    end
  end

  defp ensure_dir(entry, path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:path",
           message: "could not create directory #{path}: #{reason}",
           fix: "create #{path} manually or check parent permissions"
         )}
    end
  end

  defp check_dir_writable(entry, path) do
    cond do
      not File.dir?(path) ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:path",
           message: "path #{path} is not a directory",
           fix: "point `path:` at a directory, not a file"
         )}

      not writable?(path) ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:path",
           message: "path #{path} is not writable",
           fix: "chmod the directory so the current user can write to it"
         )}

      true ->
        :ok
    end
  end

  defp check_no_collision(entry, path) do
    replace? = Map.get(entry, :replace, false)
    dest = Path.join(path, tarball_basename(entry))

    cond do
      replace? ->
        :ok

      File.exists?(dest) ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:collision",
           message: "#{dest} already exists",
           fix: "pass `--replace` to overwrite it"
         )}

      true ->
        :ok
    end
  end

  defp check_tarball(entry) do
    app = app_from_entry(entry)
    version = version_from_entry(entry)

    case Tarball.verify(app, version) do
      :ok -> :ok
      {:error, err} -> {:error, %{err | publisher: identity(entry)}}
    end
  end

  # --- helpers ---------------------------------------------------------

  defp destination(entry, tarball) do
    path = Map.fetch!(entry, "path")
    Path.join(path, Path.basename(tarball))
  end

  defp tarball_basename(entry) do
    app = app_from_entry(entry)
    version = version_from_entry(entry)
    "#{app}-#{version}.tar.gz"
  end

  defp writable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{access: access}} when access in [:write, :read_write] -> true
      _ -> false
    end
  end

  defp app_from_entry(entry) do
    Map.get(entry, :app) || to_string(Mix.Project.config()[:app] || "")
  end

  defp version_from_entry(entry) do
    Map.get(entry, :version) || Mix.Project.config()[:version] || ""
  end

  defp identity(entry), do: ReleasePublisher.Publisher.identity(entry)
end
