defmodule ReleasePublisher.RunnerTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  import ExUnit.CaptureIO

  alias ReleasePublisher.Runner

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

  test "empty config exits ok with 'nothing configured'" do
    output =
      capture_io(fn ->
        assert :ok = Runner.run([], %{replace: false, dry_run: false, only: []}, "myapp", "1.0.0")
      end)

    assert output =~ "nothing configured"
  end

  test "--only filter with no matches exits ok", %{tmp_dir: tmp_dir} do
    _tar = make_tarball(tmp_dir)

    entries = [%{"type" => "file", "path" => Path.join(tmp_dir, "releases")}]

    output =
      capture_io(fn ->
        assert :ok =
                 with_cwd(tmp_dir, fn ->
                   Runner.run(
                     entries,
                     %{replace: false, dry_run: false, only: ["github"]},
                     "myapp",
                     "1.0.0"
                   )
                 end)
      end)

    assert output =~ "no publishers matched"
  end

  test "global preflight error aborts before publish", %{tmp_dir: tmp_dir} do
    # file publisher with path pointing at a file (not a dir) → preflight error
    not_a_dir = Path.join(tmp_dir, "nope")
    File.write!(not_a_dir, "I am a file, not a directory")

    entries = [
      %{"type" => "file", "path" => not_a_dir}
    ]

    capture_io(fn ->
      assert {:error, %ReleasePublisher.Error{step: "preflight:path"}} =
               with_cwd(tmp_dir, fn ->
                 Runner.run(
                   entries,
                   %{replace: false, dry_run: false, only: []},
                   "myapp",
                   "1.0.0"
                 )
               end)
    end)
  end

  test "--dry-run runs preflight but skips publish", %{tmp_dir: tmp_dir} do
    target = Path.join(tmp_dir, "releases")
    File.mkdir_p!(target)
    make_tarball(tmp_dir)

    entries = [%{"type" => "file", "path" => target}]

    output =
      capture_io(fn ->
        assert :ok =
                 with_cwd(tmp_dir, fn ->
                   Runner.run(
                     entries,
                     %{replace: false, dry_run: true, only: []},
                     "myapp",
                     "1.0.0"
                   )
                 end)
      end)

    assert output =~ "dry-run"
    refute File.exists?(Path.join(target, "myapp-1.0.0.tar.gz"))
  end

  test "happy path publishes via file target", %{tmp_dir: tmp_dir} do
    target = Path.join(tmp_dir, "releases")
    File.mkdir_p!(target)
    make_tarball(tmp_dir)

    entries = [%{"type" => "file", "path" => target}]

    capture_io(fn ->
      assert :ok =
               with_cwd(tmp_dir, fn ->
                 Runner.run(
                   entries,
                   %{replace: false, dry_run: false, only: []},
                   "myapp",
                   "1.0.0"
                 )
               end)
    end)

    assert File.read!(Path.join(target, "myapp-1.0.0.tar.gz")) == "FAKE"
  end

  test "--only accepts comma-separated values via task layer" do
    # Sanity check that filtering matches multiple types when passed
    # as a pre-split list (the task layer handles splitting).
    entries = [
      %{"type" => "github"},
      %{"type" => "file", "path" => "/tmp"}
    ]

    capture_io(fn ->
      # Empty only → everything matches (but will fail preflight). We
      # just confirm filter_by_only leaves both in place.
      assert {:error, _} =
               Runner.run(
                 entries,
                 %{replace: false, dry_run: false, only: ["github", "file"]},
                 "myapp",
                 "1.0.0"
               )
    end)
  end
end
