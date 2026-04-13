defmodule ReleasePublisher.TarballTest do
  use ExUnit.Case, async: false

  alias ReleasePublisher.{Error, Tarball}

  test "expected_path/2 returns the conventional path" do
    assert Tarball.expected_path(:myapp, "1.2.3") ==
             "_build/prod/myapp-1.2.3.tar.gz"

    assert Tarball.expected_path("myapp", "1.2.3") ==
             "_build/prod/myapp-1.2.3.tar.gz"
  end

  @tag :tmp_dir
  test "verify/2 returns ok when tarball exists", %{tmp_dir: tmp_dir} do
    build_dir = Path.join(tmp_dir, "_build/prod")
    File.mkdir_p!(build_dir)
    File.write!(Path.join(build_dir, "myapp-1.0.0.tar.gz"), "")

    prev = File.cwd!()
    File.cd!(tmp_dir)

    try do
      assert :ok = Tarball.verify("myapp", "1.0.0")
    after
      File.cd!(prev)
    end
  end

  @tag :tmp_dir
  test "verify/2 returns structured error when tarball is missing", %{tmp_dir: tmp_dir} do
    prev = File.cwd!()
    File.cd!(tmp_dir)

    try do
      assert {:error, %Error{step: "tarball", fix: fix}} = Tarball.verify("myapp", "1.0.0")
      assert fix =~ "mix release"
    after
      File.cd!(prev)
    end
  end
end
