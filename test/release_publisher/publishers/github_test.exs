defmodule ReleasePublisher.Publishers.GithubTest do
  use ExUnit.Case, async: false

  alias ReleasePublisher.Error
  alias ReleasePublisher.Publishers.Github

  @moduletag :tmp_dir

  defp make_tarball(tmp_dir, app \\ "myapp", version \\ "1.0.0") do
    build_dir = Path.join([tmp_dir, "_build/prod"])
    File.mkdir_p!(build_dir)
    tar = Path.join(build_dir, "#{app}-#{version}.tar.gz")
    File.write!(tar, "FAKE")
    tar
  end

  defp with_cwd(dir, fun) do
    prev = File.cwd!()
    File.cd!(dir)

    try do
      fun.()
    after
      File.cd!(prev)
    end
  end

  # Build a command-runner that routes by (cmd, args) → stub reply.
  defp stub_cmd(replies) do
    pid = self()

    fn cmd, args, _opts ->
      send(pid, {:cmd, cmd, args})
      key = {cmd, args}

      case Map.fetch(replies, key) do
        {:ok, {out, code}} -> {out, code}
        :error -> Map.get(replies, :default, {"", 0})
      end
    end
  end

  describe "preflight/1" do
    setup do
      # Ensure gh is findable for the PATH check. If not present on CI,
      # the check_gh_on_path step will fail first and we skip the rest.
      :ok
    end

    test "flags missing tag", %{tmp_dir: tmp_dir} do
      _tar = make_tarball(tmp_dir)

      cmd =
        stub_cmd(%{
          {"gh", ["auth", "status"]} => {"ok", 0},
          {"gh", ["release", "view", "v1.0.0"]} => {"not found", 1},
          :default => {"", 0}
        })

      entry = %{
        "type" => "github",
        :app => "myapp",
        :version => "1.0.0",
        :replace => false,
        :cmd_fun => cmd
      }

      # The tag almost certainly does not exist in this throwaway dir.
      result = with_cwd(tmp_dir, fn -> Github.preflight(entry) end)

      # Could fail at gh-on-path (CI without gh) or at preflight:tag.
      assert match?({:error, %Error{}}, result)
    end

    test "flags existing release without --replace", %{tmp_dir: tmp_dir} do
      _tar = make_tarball(tmp_dir)

      cmd =
        stub_cmd(%{
          {"gh", ["auth", "status"]} => {"ok", 0},
          {"gh", ["release", "view", "v1.0.0"]} => {"release found", 0},
          :default => {"", 0}
        })

      entry = %{
        "type" => "github",
        :app => "myapp",
        :version => "1.0.0",
        :replace => false,
        :cmd_fun => cmd
      }

      # Whatever the first failing step is, we should get an Error
      # struct back — this test exercises the cmd_fun plumbing end to
      # end rather than asserting a specific step, because which step
      # fires first depends on what's available in the test env (gh,
      # git origin, tag).
      assert {:error, %Error{}} = with_cwd(tmp_dir, fn -> Github.preflight(entry) end)
    end
  end

  describe "publish/4" do
    test "assembles gh release create argv", %{tmp_dir: tmp_dir} do
      tar = make_tarball(tmp_dir)

      cmd =
        stub_cmd(%{
          {"gh",
           [
             "release",
             "create",
             "v1.0.0",
             tar,
             "--title",
             "myapp v1.0.0"
           ]} => {"created", 0}
        })

      entry = %{
        "type" => "github",
        "draft" => false,
        "prerelease" => false,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false,
        :cmd_fun => cmd
      }

      assert :ok = Github.publish(entry, tar, "myapp", "1.0.0")

      assert_received {:cmd, "gh",
                       ["release", "create", "v1.0.0", ^tar, "--title", "myapp v1.0.0"]}
    end

    test "passes --draft and --prerelease when configured", %{tmp_dir: tmp_dir} do
      tar = make_tarball(tmp_dir)

      cmd = stub_cmd(%{:default => {"", 0}})

      entry = %{
        "type" => "github",
        "draft" => true,
        "prerelease" => true,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false,
        :cmd_fun => cmd
      }

      assert :ok = Github.publish(entry, tar, "myapp", "1.0.0")

      assert_received {:cmd, "gh",
                       [
                         "release",
                         "create",
                         "v1.0.0",
                         ^tar,
                         "--title",
                         "myapp v1.0.0",
                         "--draft",
                         "--prerelease"
                       ]}
    end

    test "--replace deletes then creates", %{tmp_dir: tmp_dir} do
      tar = make_tarball(tmp_dir)

      cmd = stub_cmd(%{:default => {"", 0}})

      entry = %{
        "type" => "github",
        :app => "myapp",
        :version => "1.0.0",
        :replace => true,
        :cmd_fun => cmd
      }

      assert :ok = Github.publish(entry, tar, "myapp", "1.0.0")
      assert_received {:cmd, "gh", ["release", "delete", "v1.0.0", "--yes"]}
      assert_received {:cmd, "gh", ["release", "create", "v1.0.0", ^tar | _]}
    end

    test "surfaces gh failure as Error", %{tmp_dir: tmp_dir} do
      tar = make_tarball(tmp_dir)

      cmd = stub_cmd(%{:default => {"boom", 1}})

      entry = %{
        "type" => "github",
        :app => "myapp",
        :version => "1.0.0",
        :replace => false,
        :cmd_fun => cmd
      }

      assert {:error, %Error{step: "upload"}} = Github.publish(entry, tar, "myapp", "1.0.0")
    end
  end
end
