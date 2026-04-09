defmodule ReleasePublisher.Git do
  @moduledoc """
  Thin wrapper around `git` CLI calls that `release_publisher` needs.

  The tool shells out to `git` rather than taking an Erlang git client
  dependency — this matches the "small dep tree" goal and avoids a
  second way to parse refs.
  """

  @doc """
  Return `true` if the local tag exists.
  """
  @spec tag_exists?(String.t()) :: boolean()
  def tag_exists?(tag) when is_binary(tag) do
    case System.cmd("git", ["rev-parse", "--verify", "--quiet", "refs/tags/#{tag}"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Return the URL of `origin`, or an error tuple if there is no origin.
  """
  @spec origin_url() :: {:ok, String.t()} | {:error, String.t()}
  def origin_url do
    case System.cmd("git", ["remote", "get-url", "origin"], stderr_to_stdout: true) do
      {url, 0} -> {:ok, String.trim(url)}
      {out, _} -> {:error, String.trim(out)}
    end
  end

  @doc """
  Parse a GitHub remote URL into `{owner, repo}`.

  Handles HTTPS and SSH forms, with or without a trailing `.git`:

      https://github.com/owner/repo
      https://github.com/owner/repo.git
      git@github.com:owner/repo
      git@github.com:owner/repo.git
      ssh://git@github.com/owner/repo(.git)?

  GitHub Enterprise hosts and anything that is not `github.com` are
  rejected — v1 supports github.com only.
  """
  @spec parse_github_owner_repo(String.t()) ::
          {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def parse_github_owner_repo(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      match = Regex.run(~r{^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$}, url) ->
        [_, owner, repo] = match
        {:ok, {owner, repo}}

      match = Regex.run(~r{^ssh://git@github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$}, url) ->
        [_, owner, repo] = match
        {:ok, {owner, repo}}

      match = Regex.run(~r{^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?/?$}, url) ->
        [_, owner, repo] = match
        {:ok, {owner, repo}}

      true ->
        {:error, "not a github.com remote: #{url}"}
    end
  end
end
