# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

`release_publisher` is a small, single-purpose Mix tool that **publishes an
already-built Elixir release tarball** to one or more artifact stores
(GitHub Releases, a local/mounted filesystem path). It does not build,
fetch, or deploy — it only publishes. It is the "publish" half of a
deliberate split from `relman`.

The tool is consumed exclusively via its Mix task (`mix release.publish`).
There is no public Elixir library API.

## Status

v1 is implemented. The authoritative specs remain:

- `_spec/designs/260408_InitialDesign.md` — design rationale, scope, open questions (with user-resolved answers).
- `_spec/features/260408_release-publisher-v1.md` — feature spec.
- `_spec/plans/260408_release-publisher-v1.md` — step-by-step implementation plan, including resolved open questions at the bottom.
- `README.md` — user-facing contract (flags, config shape, preflight checks).

## Commands

```bash
mix deps.get            # fetch dependencies
mix compile             # compile
mix test                # run all tests
mix test path/to/file_test.exs            # run a single test file
mix test path/to/file_test.exs:42         # run a single test by line
mix format              # format code per .formatter.exs
```

Release-flow commands this tool is designed to participate in (not run
during development of the tool itself):

```bash
mix git_ops.release     # bump version + create v<x.y.z> tag
mix release             # build tarball (owned by Elixir, not this tool)
mix release.publish     # this tool — uploads the tarball
```

## Architecture

The intended v1 module layout (per the plan):

- `Mix.Tasks.Release.Publish` — thin CLI entry point. Parses flags
  (`--init`, `--replace`, `--only`, `--dry-run`), loads config, derives
  `app` + `version` from `Mix.Project.config()`, and delegates to the runner.
- `ReleasePublisher.Runner` — orchestrates a publish run: filters by `--only`,
  executes a **global preflight pass across all publishers**, then (unless
  `--dry-run`) invokes each publisher sequentially in declared order.
  Stops on first error; no cross-publisher rollback (uploads aren't
  transactional and the tool refuses to pretend otherwise).
- `ReleasePublisher.Publisher` — behaviour with two callbacks:
  `preflight/1` and `publish/4`. Also owns the type→module dispatch map.
  Adding a publisher is purely additive.
- `ReleasePublisher.Publishers.Github` — shells out to `gh` CLI (no native
  HTTP). Preflight verifies `gh` on PATH, `gh auth status`, origin is
  github.com, tag exists, no existing release (unless `--replace`), and
  the tarball is present.
- `ReleasePublisher.Publishers.File` — `File.cp!/2` to an absolute path.
  Never auto-creates the target directory.
- `ReleasePublisher.Config` — loads `config/release_publisher.yml` via
  `yaml_elixir`. Strict: unknown keys are errors. Missing/empty config
  returns `{:ok, []}` (not an error).
- `ReleasePublisher.Git` — thin `System.cmd` wrapper: `tag_exists?/1`,
  `origin_url/0`, `parse_github_owner_repo/1` (handles both HTTPS and
  `git@github.com:` forms, with/without `.git`).
- `ReleasePublisher.Tarball` — locates `_build/prod/rel/<app>/<app>-<version>.tar.gz`.
- `ReleasePublisher.Error` — structured error (`:publisher`, `:step`, `:message`,
  `:fix`) with a `format/1` that produces the three-part error output
  used everywhere. All publishers return these, not raw strings.
- `ReleasePublisher.Init` — writes the starter YAML from `priv/templates/`.
  Refuses to overwrite an existing file; no `--force`.
- `Mix.Tasks.ReleasePublisher.Install` — Igniter installer that adds the dep,
  delegates to `--init`, and prompts to add a `release.all` alias.

### Key invariants

- **Runtime-free in consumer projects.** The tool is added with
  `only: [:dev, :test], runtime: false`, so `yaml_elixir` never ships in
  a consumer's release.
- **Global preflight, not per-publisher.** All publishers' preflight
  checks run before any upload begins. No partial state from typo'd config.
- **Shell-out over native clients.** `gh` for GitHub, `git` for tag and
  remote lookups. Keeps the dep tree small.
- **Config is a public contract.** `config/release_publisher.yml` is
  intended to be read by downstream deploy tools. Don't break its shape.
- **Convention-only tarball path** in v1. No `tarball_path:` override.
- **Error output is three lines**: publisher / step / minimal fix. No
  stack traces for user-correctable errors.
- **In GitHub publisher tests, inject a command runner** (e.g. `cmd_fun`
  in config) so tests never actually shell out to `gh`.

## Dependencies

Current runtime/dev deps (see `mix.exs`):
- `igniter` — installer framework.
- `usage_rules`, `commit_hook`, `git_ops` — repo tooling.
- `ex_doc` — docs.

v1 adds `yaml_elixir ~> 2.9` for config parsing. This is the only new
runtime dep; consumers mark the whole tool `runtime: false` so it never
ships in a consumer release.
