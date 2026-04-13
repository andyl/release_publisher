if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.ReleasePublisher.Install do
    @shortdoc "Installs release_publisher into a target project via Igniter"

    @moduledoc """
    Igniter installer for `release_publisher`.

    Adds the dep with `only: [:dev, :test], runtime: false`, runs
    `mix release.publish --init` in the target project to create the
    starter config, and prompts to add a `release.all` alias.
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        group: :release_publisher,
        example: "mix release_publisher.install"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Deps.add_dep(
        {:release_publisher, "~> 0.0", only: [:dev, :test], runtime: false}
      )
      |> write_starter_config()
      |> maybe_add_release_all_alias()
      |> Igniter.add_notice("""
      release_publisher installed.

      Next steps:
        1. Edit config/release_publisher.yml
        2. Build a release:  MIX_ENV=prod mix release
        3. Publish it:       mix release.publish
      """)
    end

    defp write_starter_config(igniter) do
      target = "config/release_publisher.yml"

      if Igniter.exists?(igniter, target) do
        Igniter.add_notice(
          igniter,
          "release_publisher: #{target} already exists — leaving it alone"
        )
      else
        contents = ReleasePublisher.Init.template_contents()
        Igniter.create_new_file(igniter, target, contents)
      end
    end

    defp maybe_add_release_all_alias(igniter) do
      if yes?(
           "Add a `release.all` alias to mix.exs that runs `mix release` then `mix release.publish`?"
         ) do
        Igniter.Project.MixProject.update(
          igniter,
          :aliases,
          [],
          fn zipper ->
            {:ok,
             Igniter.Code.List.prepend_to_list(
               zipper,
               {"release.all", ["release", "release.publish"]}
             )}
          end
        )
      else
        igniter
      end
    end

    defp yes?(prompt) do
      if function_exported?(Igniter.Util.IO, :yes?, 1) do
        Igniter.Util.IO.yes?(prompt)
      else
        # Fallback to Mix.shell() for older Igniter versions.
        Mix.shell().yes?(prompt)
      end
    end
  end
end
