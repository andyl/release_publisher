defmodule ReleasePublisher.InitTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias ReleasePublisher.{Error, Init}

  test "writes the template to a fresh target", %{tmp_dir: tmp_dir} do
    target = Path.join(tmp_dir, "config/release_publisher.yml")

    assert {:ok, ^target} = Init.run(target)
    assert File.read!(target) =~ "publish:"
    assert File.read!(target) =~ "type: github"
  end

  test "refuses to overwrite an existing file", %{tmp_dir: tmp_dir} do
    target = Path.join(tmp_dir, "config/release_publisher.yml")
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, "existing")

    assert {:error, %Error{step: "init", message: msg}} = Init.run(target)
    assert msg =~ "already exists"
    assert File.read!(target) == "existing"
  end
end
