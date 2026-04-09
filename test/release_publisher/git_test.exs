defmodule ReleasePublisher.GitTest do
  use ExUnit.Case, async: true

  alias ReleasePublisher.Git

  describe "parse_github_owner_repo/1" do
    test "parses https URLs with and without .git" do
      assert {:ok, {"owner", "repo"}} =
               Git.parse_github_owner_repo("https://github.com/owner/repo")

      assert {:ok, {"owner", "repo"}} =
               Git.parse_github_owner_repo("https://github.com/owner/repo.git")
    end

    test "parses SSH URLs with and without .git" do
      assert {:ok, {"owner", "repo"}} = Git.parse_github_owner_repo("git@github.com:owner/repo")

      assert {:ok, {"owner", "repo"}} =
               Git.parse_github_owner_repo("git@github.com:owner/repo.git")
    end

    test "parses ssh:// URLs" do
      assert {:ok, {"owner", "repo"}} =
               Git.parse_github_owner_repo("ssh://git@github.com/owner/repo.git")
    end

    test "rejects non-github hosts" do
      assert {:error, _} = Git.parse_github_owner_repo("https://gitlab.com/owner/repo")
      assert {:error, _} = Git.parse_github_owner_repo("https://github.enterprise.co/owner/repo")
    end

    test "rejects garbage input" do
      assert {:error, _} = Git.parse_github_owner_repo("not a url")
    end
  end
end
