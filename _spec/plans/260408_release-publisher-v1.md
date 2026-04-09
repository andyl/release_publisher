# Implementation Plan: Release Publisher V1

**Spec:** `_spec/features/260408_release-publisher-v1.md`
**Generated:** 2026-04-08

---

## Goal

Implement v1 of `release_pub`: a `mix release.publish` task that uploads a
pre-built Elixir release tarball to one or more configured targets
(`github`, `file`), driven by `config/release_publisher.yml`, with strict
preflight checks and clear error reporting.

## Scope

### In scope

- `Mix.Tasks.Release.Publish` task with flags: `--init`, `--replace`,
  `--only`, `--dry-run`.
- YAML config loader for `config/release_publisher.yml`.
- Publisher behaviour plus two implementations: `Github` (shells out to
  `gh`) and `File` (uses `File.cp!/2`).
- Git wrapper (tag existence, origin URL parsing).
- Tarball locator for `_build/prod/rel/<app>/<app>-<version>.tar.gz`.
- Igniter `install` task that adds the dep, writes the starter config,
  and (prompted) adds a `release.all` alias.
- Starter YAML template for `--init`.
- Unit + task-level tests for each of the above.

### Out of scope

- Building the tarball or creating git tags.
- Fetching / deploying / SSH / systemd.
- A public Elixir library API.
- Signing, checksums, release notes sourcing.
- Additional publishers (rsync, scp, s3, http-put).
- `config.exs` as an alternate config location.
- `--init --force`, `tarball_path:` override, cross-publisher rollback.

## Architecture & Design Decisions

- **Existing namespace is `ReleasePub` / `:release_pub`**, not
  `ReleasePublisher`. All new modules will live under `ReleasePub.*` to
  match `lib/release_pub.ex` and `mix.exs`. The spec's
  `ReleasePublisher.*` names are mapped to `ReleasePub.*` 1:1. (Flag this
  during implementation in case the project is being renamed.)
- **Single Mix task entry point**, `Mix.Tasks.Release.Publish`, already
  stubbed at `lib/mix/tasks/release.publish.ex`. All CLI parsing,
  dispatch, and reporting live there; business logic is delegated to
  `ReleasePub.*` modules so the task stays thin and testable.
- **Publisher behaviour with two callbacks** (`preflight/1`, `publish/4`)
  plus a type→module dispatch map in one place
  (`ReleasePub.Publisher`). Adding a publisher is additive.
- **Shell-out over native clients**: `gh` for GitHub, `git` for tag /
  remote lookups. Matches the spec's "small dep tree" requirement and
  the existing habit of the target audience.
- **YAML parsing via `yaml_elixir`**. No YAML dep exists yet; add it.
  Picked because it is the de-facto Elixir YAML parser and has no
  problematic transitive deps. (If we prefer to avoid a new dep, the
  alternative is a tiny handwritten subset parser, but that is fragile
  and not recommended.)
- **Config is strict.** Unknown keys at the publisher level are an
  error, not silently ignored — typo'd config should fail loudly, in
  keeping with the spec's preflight philosophy.
- **Error type is structured**, not raw strings. Each publisher returns
  `{:error, %ReleasePub.Error{publisher: ..., step: ..., message: ...,
  fix: ...}}`. The task formats these into the three-part error message
  (publisher / step / minimal fix) in one place, so all error output
  looks the same.
- **Preflight runs per-publisher, not globally.** The spec leaves this
  as an open question; per-publisher keeps the code simpler and still
  catches typos before any upload because preflight still runs before
  every publish call. Document the tradeoff in the task's moduledoc.
- **Tarball path is convention-only in v1**:
  `_build/prod/rel/<app>/<app>-<version>.tar.gz`. `<app>` comes from
  `Mix.Project.config()[:app]`, `<version>` from `@version` in mix.exs.
- **No runtime application**: `release_pub` is a dev/test tool. Keep
  it out of `application/0` children and make sure the task works under
  `Mix.Task.run/2` without starting a supervision tree.

## Implementation Steps

1. **Add `yaml_elixir` dependency**
   - Files: `mix.exs`, `mix.lock`
   - Details: Add `{:yaml_elixir, "~> 2.9"}` to `deps/0`. Run
     `mix deps.get` to update the lockfile. This is the only new runtime
     dep; justify in the commit message.

2. **Create the `ReleasePub.Error` struct**
   - Files: `lib/release_pub/error.ex`
   - Details: Struct with fields `:publisher`, `:step`, `:message`,
     `:fix`. Provide `format/1` that returns the three-line message the
     task prints. Keep it dumb — no logic, just formatting.

3. **Create the Git helper module**
   - Files: `lib/release_pub/git.ex`
   - Details: Functions `tag_exists?/1`, `origin_url/0`,
     `parse_github_owner_repo/1`. `parse_github_owner_repo/1` must
     handle both `https://github.com/owner/repo(.git)?` and
     `git@github.com:owner/repo(.git)?`. Shell out via `System.cmd/3`
     with stderr captured; return `{:ok, _}` / `{:error, _}` tuples.

4. **Create the Tarball locator**
   - Files: `lib/release_pub/tarball.ex`
   - Details: `expected_path(app, version)` returns the convention path.
     `verify!(app, version)` returns `:ok` or an error struct telling
     the user to run `mix release` first.

5. **Define the Publisher behaviour and dispatch**
   - Files: `lib/release_pub/publisher.ex`
   - Details: `@callback preflight(map) :: :ok | {:error, term}` and
     `@callback publish(map, Path.t, String.t, String.t) :: :ok |
     {:error, term}`. Provide `dispatch/1` that maps
     `%{"type" => "github"}` → `ReleasePub.Publishers.Github`, etc.
     Include `identity/1` for building things like
     `file[/mnt/releases/myapp]` used in error messages.

6. **Implement `ReleasePub.Publishers.Github`**
   - Files: `lib/release_pub/publishers/github.ex`
   - Details: Preflight steps in order: `gh` on PATH
     (`System.find_executable/1`), `gh auth status`, parse origin,
     verify tag, check for an existing release
     (`gh release view v<version>`), verify tarball exists. `publish/4`
     runs `gh release create ...` with `--title` and optional `--draft`
     / `--prerelease` (from config). When `--replace` is in effect,
     delete-then-create. Map every failure into `ReleasePub.Error` with
     a concrete `fix:` string.

7. **Implement `ReleasePub.Publishers.File`**
   - Files: `lib/release_pub/publishers/file.ex`
   - Details: Preflight: `path` set, absolute, exists, writable, no
     collision with `<app>-<version>.tar.gz`, tarball present.
     `publish/4` uses `File.cp!/2`. `--replace` overwrites in place.

8. **Config loader**
   - Files: `lib/release_pub/config.ex`
   - Details: Reads `config/release_publisher.yml` via `YamlElixir`.
     Returns `{:ok, [publisher_entry]}` or a structured error for
     malformed YAML / unknown publisher type / missing required keys.
     Missing file, empty file, or missing `publish:` all return
     `{:ok, []}`. Preserves declared order.

9. **Starter template + `--init` writer**
   - Files: `lib/release_pub/init.ex`, plus the template string inline
     or under `priv/templates/release_publisher.yml`
   - Details: Write `config/release_publisher.yml` from the starter
     (github uncommented, file commented) only when no file exists.
     Otherwise print a message pointing at the existing file and exit
     non-zero. No `--force`.

10. **Runner / orchestrator**
    - Files: `lib/release_pub/runner.ex`
    - Details: Given the parsed config, flags (`:replace`, `:only`,
      `:dry_run`), app, and version: filter by `:only`, for each
      publisher run preflight then (unless `:dry_run`) publish, collect
      results, print per-publisher status lines. Stops on first error
      and returns `{:error, formatted}`. No partial rollback.

11. **Wire the Mix task**
    - Files: `lib/mix/tasks/release.publish.ex`
    - Details: Replace the stub with a real implementation.
      `OptionParser` for flags (`--init`, `--replace`, `--only` as
      `:keep`, `:dry_run`). On `--init`, delegate to
      `ReleasePub.Init.run/0`. Otherwise: load config, derive `app` +
      `version` from `Mix.Project.config()`, verify `v<version>` tag,
      verify tarball, invoke `ReleasePub.Runner.run/3`. Print errors via
      `ReleasePub.Error.format/1` and call `Mix.raise/1` (or
      `System.halt/1`) for non-zero exit.

12. **Igniter install task**
    - Files: `lib/mix/tasks/release_pub.install.ex`
    - Details: Use Igniter to add
      `{:release_pub, "~> 0.0", only: [:dev, :test], runtime: false}`
      to the target project's deps, invoke
      `Mix.Tasks.Release.Publish.run(["--init"])` in the target
      project's context to create the config, and prompt (via
      `Igniter.Util.IO.yes?/1` or equivalent) to add the
      `release.all` alias. Print next-step instructions.

13. **Delete the placeholder module and test**
    - Files: `lib/release_pub.ex`, `test/release_pub_test.exs`
    - Details: Remove the `hello/0` example and its doctest. Replace
      with an empty module (`@moduledoc false`) or delete the file if
      nothing else depends on it. Update/remove the matching test.

14. **Unit tests — Git helper**
    - Files: `test/release_pub/git_test.exs`
    - Details: Table-driven tests for `parse_github_owner_repo/1`
      covering HTTPS, SSH, with/without `.git` suffix, and non-github
      URLs (negative case).

15. **Unit tests — Config loader**
    - Files: `test/release_pub/config_test.exs`,
      `test/fixtures/config/*.yml`
    - Details: Valid mixed publishers preserved in order; empty /
      missing `publish:`; malformed YAML; unknown publisher type;
      missing required keys (`file` without `path`).

16. **Unit tests — File publisher**
    - Files: `test/release_pub/publishers/file_test.exs`
    - Details: Happy-path copy in a `tmp_dir` ExUnit tag. Each preflight
      failure mode (non-absolute, missing, non-writable, existing file
      without `--replace`, missing tarball). `--replace` overwrites in
      place.

17. **Unit tests — GitHub publisher (stubbed)**
    - Files: `test/release_pub/publishers/github_test.exs`
    - Details: Inject a command runner (e.g. `cmd_fun` in the config
      map) so tests do not shell out. Verify each preflight failure
      mode produces a distinct `ReleasePub.Error` with a helpful
      `fix:`. Verify the upload assembles the right `gh` argv, and
      that `--replace` triggers delete-then-create.

18. **Unit tests — Init writer**
    - Files: `test/release_pub/init_test.exs`
    - Details: Writes the template into a `tmp_dir`; second run refuses
      to overwrite and returns an error.

19. **Task-level tests — `mix release.publish`**
    - Files: `test/mix/tasks/release.publish_test.exs`
    - Details: Exercise the task with all boundaries stubbed:
      `--only` filters by type, `--dry-run` skips the publish callback
      but still runs preflight, `--replace` propagates, empty config
      exits 0 with a message, missing tarball aborts, unknown `--only`
      type exits 0 with "no publishers matched".

20. **Task-level test — `--init`**
    - Files: `test/mix/tasks/release.publish_init_test.exs`
    - Details: Confirms `--init` writes the file and exits without
      running any publishers.

21. **Igniter install test**
    - Files: `test/mix/tasks/release_pub.install_test.exs`
    - Details: Use Igniter's test helpers to run the installer against
      a synthetic project and assert dep / config / alias outcomes.

22. **Update README**
    - Files: `README.md`
    - Details: Replace the placeholder with a short real intro: what
      the tool does, how to install, how to configure, and the typical
      three-command flow (`mix git_ops.release && mix release && mix
      release.publish`). Mention that
      `config/release_publisher.yml` is a stable public contract for
      downstream deploy tools.

## Dependencies & Ordering

- Step 1 (`yaml_elixir` dep) must land before step 8 (Config loader)
  and any test that loads YAML.
- Step 2 (`Error`) is used by steps 3–11 — land it first so everything
  else can return structured errors.
- Steps 3–4 (Git, Tarball) are independent and can land in either
  order, but both are prerequisites for the publishers (6, 7) and the
  task (11).
- Step 5 (Publisher behaviour + dispatch) must land before steps 6 and
  7 so the publishers have something to `@behaviour`.
- Steps 6 and 7 are independent of each other.
- Step 8 (Config) depends only on Step 1 and Step 2.
- Step 9 (`--init`) depends on the starter template only; it does not
  need the runner.
- Step 10 (Runner) depends on 5, 6, 7, 8, and the Error struct.
- Step 11 (Mix task wiring) depends on 9 and 10.
- Step 12 (Igniter install) depends on 11 because it delegates to
  `mix release.publish --init`.
- Step 13 (placeholder cleanup) can happen any time after step 2 —
  land it early so the module tree is clean.
- Tests (14–21) follow their corresponding implementation steps.
- README (22) is last so it describes what actually shipped.

## Edge Cases & Risks

- **Namespace mismatch**: The spec uses `ReleasePublisher.*` but the
  project is `release_pub` / `ReleasePub`. Plan sticks with
  `ReleasePub.*` to avoid a rename mid-feature. If the user actually
  wants to rename the project, that is a separate PR that must land
  first.
- **YAML dep**: Adding `yaml_elixir` is the first runtime dep beyond
  the existing tooling. Worth calling out in the PR description.
- **`gh` output parsing for "release exists" check**: `gh release view`
  returns non-zero when the release is missing, which is convenient,
  but its stderr message format can vary. Match on exit code, not
  stderr text.
- **Origin URL parsing edge cases**: trailing `.git`, `ssh://`-style
  URLs (`ssh://git@github.com/owner/repo.git`), and GitHub Enterprise
  hosts. v1 supports only `github.com`; GHE returns a "not a
  github.com remote" error.
- **File publisher + relative `path`**: explicitly rejected in
  preflight so typos do not silently write into the current directory.
- **File publisher overwrite race**: between preflight's "no
  collision" check and the `File.cp!` call, another process could
  create the target. Acceptable in v1; the error from `File.cp!` will
  still surface, just less prettily.
- **`--only` filter with empty result**: exit 0 with "no publishers
  matched" — do not error, per the spec's idempotency-friendly tone.
- **Umbrella / multi-release projects**: v1 assumes one release per
  project. Detect `releases:` with more than one entry in
  `Mix.Project.config()` and print a clear "not supported in v1"
  error rather than publishing the wrong thing.
- **`gh` auth mid-run**: `gh auth status` may succeed in preflight but
  the token could expire before upload. Accept the risk; surface the
  resulting `gh` error unchanged.
- **Partial publish across publishers**: documented, not hidden. The
  runner prints which publishers completed before the failing one so
  the user can reason about state.
- **Tarball built in a different `MIX_ENV`**: the convention path is
  `_build/prod/...`. If the user built under a different env, the
  preflight "missing tarball" error is the right outcome; the fix
  string should mention `MIX_ENV=prod mix release`.

## Testing Strategy

- **Unit tests** for pure modules (Git parser, Config loader, Tarball
  path, Error formatter, Init writer).
- **Publisher tests** with command-runner injection so `gh` is never
  actually invoked; verify argv assembly and error classification.
  File publisher uses real `File` ops under `@tag :tmp_dir`.
- **Task-level tests** drive `Mix.Tasks.Release.Publish.run/1` with
  stubs for Git/tarball/publisher boundaries and assert output,
  exit behavior, and flag handling.
- **Igniter install test** using Igniter's test helpers to assert
  deps, config file creation, and alias prompt behavior.
- **Manual smoke test** before merge: in a throwaway repo with `gh`
  authed, run `mix release.publish --init`, edit the config, run
  `mix release`, run `mix release.publish`, confirm the release
  appears on GitHub and (if a `file` target is configured) the
  tarball lands in the right directory. Then re-run without flags
  and confirm the error; re-run with `--replace` and confirm
  overwrite.

## Open Questions

- [x] Is the project being renamed from `release_pub` to
      `release_publisher`? The spec and design doc consistently say
      `release_publisher`, but `mix.exs` / `lib/release_pub.ex` say
      `release_pub`. Plan assumes the existing name stays; confirm
      before merge.  Answer: let's rename to `release_publisher`.
- [x] OK to add `yaml_elixir` as a runtime dep, or should YAML parsing
      be kept out of the runtime dep tree (e.g., by putting the whole
      tool behind `only: [:dev, :test]`)? Recommendation: mark
      `release_pub` itself `runtime: false` in consumer projects (the
      Igniter install already does this) so `yaml_elixir` only loads
      at publish time.  Answer: I'll go with your recommendations
- [x] Should `--only` accept comma-separated values
      (`--only github,file`) in addition to being repeatable? Spec
      only requires repeatable; plan follows the spec.  Answer: yes, allow a comma-separated list
- [x] Global preflight pass (all publishers) vs. per-publisher
      preflight-then-publish. Plan picks per-publisher; flag for
      review if reviewers prefer global.  Answer: I prefer global pre-flight
- [x] Where should the starter YAML template live — inline string in
      `ReleasePub.Init`, or a file under `priv/templates/`? Plan
      leans toward `priv/templates/` for editability.  Answer: I like a template under priv/templates
