defmodule ReleasePublisher.Publishers.FileTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias ReleasePublisher.Error
  alias ReleasePublisher.Publishers.File, as: FilePub

  defp make_tarball(tmp_dir, app \\ "myapp", version \\ "1.0.0") do
    # Build the conventional path for Tarball.verify to find.
    rel_dir = Path.join([tmp_dir, "_build/prod/rel/#{app}"])
    File.mkdir_p!(rel_dir)
    tar = Path.join(rel_dir, "#{app}-#{version}.tar.gz")
    File.write!(tar, "FAKE TARBALL")
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

  describe "preflight/1" do
    test "happy path", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "releases")
      File.mkdir_p!(target)
      _tar = make_tarball(tmp_dir)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false
      }

      assert :ok = with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)
    end

    test "rejects relative path", %{tmp_dir: tmp_dir} do
      entry = %{"type" => "file", "path" => "relative/dir", :app => "myapp", :version => "1.0.0"}

      assert {:error, %Error{step: "preflight:path", message: msg}} =
               with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)

      assert msg =~ "not absolute"
    end

    test "auto-creates missing directory", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "new/nested/dir")
      _tar = make_tarball(tmp_dir)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false
      }

      assert :ok = with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)
      assert File.dir?(target)
    end

    test "expands tilde path", %{tmp_dir: tmp_dir} do
      _tar = make_tarball(tmp_dir)
      home = System.user_home!()

      entry = %{
        "type" => "file",
        "path" => "~/some_release_dir_test",
        :app => "myapp",
        :version => "1.0.0",
        :replace => false
      }

      expanded = Path.join(home, "some_release_dir_test")

      try do
        assert :ok = with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)
        assert File.dir?(expanded)
      after
        File.rm_rf!(expanded)
      end
    end

    test "rejects ~user/ path syntax", %{tmp_dir: tmp_dir} do
      entry = %{
        "type" => "file",
        "path" => "~otheruser/releases",
        :app => "myapp",
        :version => "1.0.0"
      }

      assert {:error, %Error{step: "preflight:path", message: msg}} =
               with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)

      assert msg =~ "~user syntax"
    end

    test "rejects collision without --replace", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "releases")
      File.mkdir_p!(target)
      File.write!(Path.join(target, "myapp-1.0.0.tar.gz"), "existing")
      _tar = make_tarball(tmp_dir)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false
      }

      assert {:error, %Error{step: "preflight:collision"}} =
               with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)
    end

    test "allows collision with --replace", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "releases")
      File.mkdir_p!(target)
      File.write!(Path.join(target, "myapp-1.0.0.tar.gz"), "existing")
      _tar = make_tarball(tmp_dir)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => true
      }

      assert :ok = with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)
    end

    test "reports missing tarball", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "releases")
      File.mkdir_p!(target)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false
      }

      assert {:error, %Error{step: "tarball"}} =
               with_cwd(tmp_dir, fn -> FilePub.preflight(entry) end)
    end
  end

  describe "publish/4" do
    test "copies tarball into target directory", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "releases")
      File.mkdir_p!(target)
      tar = make_tarball(tmp_dir)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => false
      }

      assert :ok = FilePub.publish(entry, tar, "myapp", "1.0.0")
      assert File.read!(Path.join(target, "myapp-1.0.0.tar.gz")) == "FAKE TARBALL"
    end

    test "--replace overwrites in place", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "releases")
      File.mkdir_p!(target)
      existing = Path.join(target, "myapp-1.0.0.tar.gz")
      File.write!(existing, "OLD")
      tar = make_tarball(tmp_dir)

      entry = %{
        "type" => "file",
        "path" => target,
        :app => "myapp",
        :version => "1.0.0",
        :replace => true
      }

      assert :ok = FilePub.publish(entry, tar, "myapp", "1.0.0")
      assert File.read!(existing) == "FAKE TARBALL"
    end
  end
end
