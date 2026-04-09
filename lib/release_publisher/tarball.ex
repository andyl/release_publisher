defmodule ReleasePublisher.Tarball do
  @moduledoc """
  Locates the pre-built release tarball.

  `release_publisher` does not build releases; it expects `mix release`
  to have already produced a tarball at the conventional path:

      _build/prod/rel/<app>/<app>-<version>.tar.gz

  The path is convention-only in v1. There is no `tarball_path:`
  override in the config.
  """

  alias ReleasePublisher.Error

  @doc """
  Return the conventional path for `<app>-<version>.tar.gz`.
  """
  @spec expected_path(atom() | String.t(), String.t()) :: Path.t()
  def expected_path(app, version) do
    app_str = to_string(app)
    Path.join(["_build", "prod", "rel", app_str, "#{app_str}-#{version}.tar.gz"])
  end

  @doc """
  Verify that the tarball exists at the conventional path.

  Returns `:ok` or `{:error, %ReleasePublisher.Error{}}`.
  """
  @spec verify(atom() | String.t(), String.t()) :: :ok | {:error, Error.t()}
  def verify(app, version) do
    path = expected_path(app, version)

    if File.regular?(path) do
      :ok
    else
      {:error,
       Error.new(
         publisher: "release_publisher",
         step: "tarball",
         message: "expected release tarball at #{path}",
         fix: "run `MIX_ENV=prod mix release` first"
       )}
    end
  end
end
