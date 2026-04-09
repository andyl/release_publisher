defmodule ReleasePublisher.Init do
  @moduledoc """
  Handles `mix release.publish --init`: writes a starter
  `config/release_publisher.yml` from the template under
  `priv/templates/`.

  Refuses to overwrite an existing file. There is no `--force` in v1 —
  if the user wants to regenerate, they can delete the file first.
  """

  alias ReleasePublisher.Error

  @default_target "config/release_publisher.yml"
  @template_path "priv/templates/release_publisher.yml"

  @doc """
  Write the starter template to the default target path.
  """
  @spec run() :: {:ok, Path.t()} | {:error, Error.t()}
  def run, do: run(@default_target)

  @doc """
  Write the starter template to `target`. Will not overwrite an
  existing file.
  """
  @spec run(Path.t()) :: {:ok, Path.t()} | {:error, Error.t()}
  def run(target) do
    if File.exists?(target) do
      {:error,
       Error.new(
         publisher: "release_publisher",
         step: "init",
         message: "#{target} already exists",
         fix: "delete the file first if you want to regenerate it"
       )}
    else
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, template_contents())
      {:ok, target}
    end
  end

  @doc """
  The raw template contents that will be written by `run/0`.
  """
  @spec template_contents() :: String.t()
  def template_contents do
    case :code.priv_dir(:release_publisher) do
      {:error, :bad_name} ->
        # Not running under a compiled app (e.g. direct script use);
        # fall back to the in-repo path.
        File.read!(@template_path)

      priv ->
        priv
        |> Path.join("templates/release_publisher.yml")
        |> File.read!()
    end
  end
end
