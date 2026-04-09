defmodule ReleasePublisher.Publishers.Github do
  @moduledoc """
  Publishes a release tarball to GitHub Releases via the `gh` CLI.

  Preflight (in order):

    1. `gh` is on PATH.
    2. `gh auth status` exits 0.
    3. `git remote get-url origin` parses as a github.com URL.
    4. Local tag `v<version>` exists.
    5. No existing release for `v<version>` (unless `--replace`).
    6. Tarball exists at the conventional path.

  `publish/4` runs `gh release create`, passing `--title`, and
  optionally `--draft` / `--prerelease` from the config entry. When
  `--replace` is in effect, an existing release is deleted first.

  ## Command runner injection

  To keep tests fast and hermetic, the publisher never calls
  `System.cmd/3` directly. Instead it uses the `:cmd_fun` from the
  entry map (or a default that wraps `System.cmd/3`). Tests inject a
  stub and assert on the argv passed to `gh`.

  The function must have the shape
  `fun.(cmd, args, opts) :: {binary, exit_code}`.
  """

  @behaviour ReleasePublisher.Publisher

  alias ReleasePublisher.{Error, Git, Tarball}

  @impl true
  def preflight(entry) do
    with :ok <- check_gh_on_path(entry),
         :ok <- check_gh_auth(entry),
         {:ok, _owner_repo} <- check_origin(),
         :ok <- check_tag(entry),
         :ok <- check_no_existing_release(entry),
         :ok <- check_tarball(entry) do
      :ok
    end
  end

  @impl true
  def publish(entry, tarball, app, version) do
    cmd = cmd_fun(entry)
    tag = "v#{version}"
    replace? = Map.get(entry, :replace, false)

    with :ok <- maybe_delete_existing(replace?, entry, cmd, tag) do
      argv = build_create_argv(entry, tag, tarball, app, version)

      case cmd.("gh", argv, stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        {out, _} ->
          {:error,
           Error.new(
             publisher: identity(entry),
             step: "upload",
             message: "gh release create failed: #{String.trim(out)}",
             fix: "inspect the gh output above and retry"
           )}
      end
    end
  end

  # --- preflight steps -------------------------------------------------

  defp check_gh_on_path(entry) do
    if System.find_executable("gh") do
      :ok
    else
      {:error,
       Error.new(
         publisher: identity(entry),
         step: "preflight:gh-on-path",
         message: "`gh` CLI not found on $PATH",
         fix: "install the GitHub CLI (https://cli.github.com/)"
       )}
    end
  end

  defp check_gh_auth(entry) do
    cmd = cmd_fun(entry)

    case cmd.("gh", ["auth", "status"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {out, _} ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:gh-auth",
           message: "`gh auth status` failed: #{String.trim(out)}",
           fix: "run `gh auth login`"
         )}
    end
  end

  defp check_origin do
    case Git.origin_url() do
      {:ok, url} ->
        case Git.parse_github_owner_repo(url) do
          {:ok, owner_repo} ->
            {:ok, owner_repo}

          {:error, msg} ->
            {:error,
             Error.new(
               publisher: "github",
               step: "preflight:origin",
               message: msg,
               fix: "v1 supports only github.com origins"
             )}
        end

      {:error, msg} ->
        {:error,
         Error.new(
           publisher: "github",
           step: "preflight:origin",
           message: "could not read origin URL: #{msg}",
           fix: "add a github.com remote named `origin`"
         )}
    end
  end

  defp check_tag(entry) do
    version = version_from_entry(entry)
    tag = "v#{version}"

    if Git.tag_exists?(tag) do
      :ok
    else
      {:error,
       Error.new(
         publisher: identity(entry),
         step: "preflight:tag",
         message: "local git tag #{tag} not found",
         fix: "run `mix git_ops.release` to create the tag"
       )}
    end
  end

  defp check_no_existing_release(entry) do
    cmd = cmd_fun(entry)
    replace? = Map.get(entry, :replace, false)
    tag = "v#{version_from_entry(entry)}"

    case cmd.("gh", ["release", "view", tag], stderr_to_stdout: true) do
      {_, 0} when replace? ->
        :ok

      {_, 0} ->
        {:error,
         Error.new(
           publisher: identity(entry),
           step: "preflight:existing-release",
           message: "GitHub release #{tag} already exists",
           fix: "pass `--replace` to overwrite it"
         )}

      {_, _} ->
        # non-zero exit means "no such release" (or some other gh error).
        # The upload step will surface other gh errors if any.
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

  # --- publish helpers -------------------------------------------------

  defp maybe_delete_existing(false, _entry, _cmd, _tag), do: :ok

  defp maybe_delete_existing(true, entry, cmd, tag) do
    case cmd.("gh", ["release", "delete", tag, "--yes"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {_, _} ->
        # If delete fails because there is no release, create will
        # succeed. Swallow the error and let create surface real
        # problems.
        _ = entry
        :ok
    end
  end

  defp build_create_argv(entry, tag, tarball, app, version) do
    title = "#{app} v#{version}"

    base = ["release", "create", tag, tarball, "--title", title]

    base
    |> maybe_flag("--draft", Map.get(entry, "draft", false))
    |> maybe_flag("--prerelease", Map.get(entry, "prerelease", false))
  end

  defp maybe_flag(argv, _flag, false), do: argv
  defp maybe_flag(argv, _flag, nil), do: argv
  defp maybe_flag(argv, flag, true), do: argv ++ [flag]

  # --- helpers ---------------------------------------------------------

  defp cmd_fun(entry) do
    Map.get(entry, :cmd_fun, &System.cmd/3)
  end

  defp app_from_entry(entry) do
    Map.get(entry, :app) || to_string(Mix.Project.config()[:app] || "")
  end

  defp version_from_entry(entry) do
    Map.get(entry, :version) || Mix.Project.config()[:version] || ""
  end

  defp identity(entry), do: ReleasePublisher.Publisher.identity(entry)
end
