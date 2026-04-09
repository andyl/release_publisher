defmodule ReleasePublisher.PublisherTest do
  use ExUnit.Case, async: true

  alias ReleasePublisher.{Error, Publisher}

  doctest Publisher

  test "dispatch/1 resolves known types" do
    assert {:ok, ReleasePublisher.Publishers.Github} = Publisher.dispatch(%{"type" => "github"})
    assert {:ok, ReleasePublisher.Publishers.File} = Publisher.dispatch(%{"type" => "file"})
  end

  test "dispatch/1 errors on unknown type" do
    assert {:error, %Error{step: "config"}} = Publisher.dispatch(%{"type" => "rsync"})
  end

  test "identity/1 builds per-type identities" do
    assert Publisher.identity(%{"type" => "github"}) == "github"

    assert Publisher.identity(%{"type" => "file", "path" => "/mnt/rel"}) ==
             "file[/mnt/rel]"
  end
end
