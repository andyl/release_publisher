defmodule ReleasePublisher.ErrorTest do
  use ExUnit.Case, async: true

  alias ReleasePublisher.Error

  test "format/1 renders publisher, step, message, fix" do
    err =
      Error.new(
        publisher: "file[/tmp/rel]",
        step: "preflight:path",
        message: "path /tmp/rel does not exist",
        fix: "create /tmp/rel"
      )

    formatted = Error.format(err)

    assert formatted =~ "file[/tmp/rel]: preflight:path failed"
    assert formatted =~ "path /tmp/rel does not exist"
    assert formatted =~ "fix: create /tmp/rel"
  end

  test "format/1 omits fix line when fix is nil" do
    err = Error.new(publisher: "github", step: "upload", message: "boom", fix: nil)
    refute Error.format(err) =~ "fix:"
  end
end
