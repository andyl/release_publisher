defmodule ReleasePublisher.ConfigTest do
  use ExUnit.Case, async: true

  alias ReleasePublisher.{Config, Error}

  @fixtures Path.expand("../fixtures/config", __DIR__)

  test "missing file returns empty list" do
    assert {:ok, []} = Config.load(Path.join(@fixtures, "does_not_exist.yml"))
  end

  test "empty file returns empty list" do
    assert {:ok, []} = Config.load(Path.join(@fixtures, "empty.yml"))
  end

  test "missing publish: key returns empty list" do
    assert {:ok, []} = Config.load(Path.join(@fixtures, "no_publish_key.yml"))
  end

  test "valid mixed publishers preserves declared order" do
    assert {:ok, [first, second]} = Config.load(Path.join(@fixtures, "valid_mixed.yml"))
    assert first["type"] == "github"
    assert second["type"] == "file"
    assert second["path"] == "/mnt/releases/myapp"
  end

  test "malformed YAML is a structured error" do
    assert {:error, %Error{step: "config"}} =
             Config.load(Path.join(@fixtures, "malformed.yml"))
  end

  test "unknown publisher type is an error" do
    assert {:error, %Error{step: "config", message: msg}} =
             Config.load(Path.join(@fixtures, "unknown_type.yml"))

    assert msg =~ "unknown type"
  end

  test "file publisher without path is an error" do
    assert {:error, %Error{step: "config", message: msg}} =
             Config.load(Path.join(@fixtures, "file_missing_path.yml"))

    assert msg =~ "path"
  end

  test "unknown key at publisher level is an error" do
    assert {:error, %Error{step: "config", message: msg}} =
             Config.load(Path.join(@fixtures, "unknown_key.yml"))

    assert msg =~ "unknown keys"
  end
end
