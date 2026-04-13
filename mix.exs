defmodule ReleasePublisher.MixProject do
  use Mix.Project

  @version "0.2.1"

  def project do
    [
      app: :release_publisher,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # YAML parsing for config/release_publisher.yml.
      # Consumers add this tool with `runtime: false`, so yaml_elixir
      # only loads at publish time and never ships in a consumer release.
      {:yaml_elixir, "~> 2.9"},
      # Repo Tooling
      {:igniter, "~> 0.6"},
      # AI Tooling
      {:usage_rules, "~> 1.2", only: [:dev, :test]},
      # Conventional Commits, Releases
      {:commit_hook, "~> 0.4"},
      {:git_ops, "~> 2.0", only: [:dev, :test], runtime: false},
      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
