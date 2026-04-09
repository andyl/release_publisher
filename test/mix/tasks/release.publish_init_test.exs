defmodule Mix.Tasks.Release.PublishInitTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  import ExUnit.CaptureIO

  defp with_cwd(dir, fun) do
    prev = File.cwd!()
    File.cd!(dir)

    try do
      fun.()
    after
      File.cd!(prev)
    end
  end

  test "--init writes the starter config and exits without publishing", %{tmp_dir: tmp_dir} do
    capture_io(fn ->
      with_cwd(tmp_dir, fn ->
        Mix.Tasks.Release.Publish.run(["--init"])
      end)
    end)

    target = Path.join(tmp_dir, "config/release_publisher.yml")
    assert File.exists?(target)
    assert File.read!(target) =~ "publish:"
  end

  test "--init refuses to overwrite an existing file", %{tmp_dir: tmp_dir} do
    target = Path.join(tmp_dir, "config/release_publisher.yml")
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, "existing")

    assert_raise Mix.Error, fn ->
      capture_io(:stderr, fn ->
        with_cwd(tmp_dir, fn ->
          Mix.Tasks.Release.Publish.run(["--init"])
        end)
      end)
    end

    assert File.read!(target) == "existing"
  end
end
