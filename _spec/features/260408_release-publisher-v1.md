# Feature Specification: release-publisher-v1

## Overview

Deliver v1 of `release_publisher`: a small, single-purpose Mix tool that
publishes an already-built Elixir release tarball to one or more artifact
stores. It does not build, fetch, or deploy — it only publishes.

This feature covers the initial implementation as described in
`_spec/designs/260408_InitialDesign.md`. The scope is a single Mix task
(`mix release.publish`), a YAML config file, two publishers (`github` and
`file`), and an Igniter `install` task.

## Goals

- Ship a Mix task `mix release.publish` that reliably uploads a pre-built
  release tarball to all configured targets.
- Keep the tool's surface area minimal: one task, one config file, two
  publishers, no library API.
- Make the seam between "build" and "publish" obvious so consumer projects
  can compose `mix release` and `mix release.publish` via aliases.
- Establish `config/release_publisher.yml` as a stable public contract that
  downstream deploy tools can read to discover published artifacts.
- Fail fast and clearly: preflight checks run before any upload, and all
  error messages name the failing publisher, the failing step, and the
  minimal fix.

### Success criteria

- `mix release.publish` publishes a known-good tarball to both a GitHub
  release and a local filesystem path, in one run, with no manual steps.
- Re-running the same command without flags errors out rather than silently
  overwriting.
- `mix release.publish --init` writes a usable starter config.
- `mix igniter.install release_publisher` leaves a fresh project in a
  committable, ready-to-edit state.

## Functional Requirements

### Mix task: `mix release.publish`

- Reads `@version` from `mix.exs`.
- Loads `config/release_publisher.yml`. Missing/empty `publish:` exits 0
  with a "nothing configured" message.
- For each configured publisher, in declared order:
  1. Run the publisher's `preflight/1` check.
  2. Locate the local tarball for `@version`. Abort with a clear message
     telling the user to run `mix release` first if missing.
  3. Verify the local git tag `v<@version>` exists. Abort if missing.
  4. Invoke the publisher's `publish/4` action.
  5. Report success for the publisher.
- Publishers run sequentially. The first error stops the run; previously
  completed publishers are not rolled back (documented, not hidden).

### Flags

| Flag            | Effect                                                                  |
|-----------------|-------------------------------------------------------------------------|
| `--init`        | Write a starter `config/release_publisher.yml` and exit. No publish.    |
| `--replace`     | If the artifact already exists at the target, delete and recreate it.  |
| `--only <type>` | Run only publishers of a given type. Repeatable.                       |
| `--dry-run`     | Run preflight + report what would be published. No upload.            |

No `--force` and no `--from-release` flags.

### `mix release.publish --init`

- Writes `config/release_publisher.yml` from a commented starter template
  that contains the full publisher shape.
- Refuses to overwrite an existing file; points the user at the existing
  path. No `--force` regeneration.

### Config: `config/release_publisher.yml`

- YAML file at `config/release_publisher.yml`.
- Top-level `publish:` is an ordered list of publisher entries. Each entry
  has a `type:` plus publisher-specific keys.
- The same `type` may appear multiple times (e.g. two `file` targets).
- Omitting or emptying `publish:` is not an error.

### GitHub publisher

- Shells out to the `gh` CLI.
- Preflight checks (in order, fail fast):
  1. `gh` is on `$PATH`.
  2. `gh auth status` exits 0.
  3. `git remote get-url origin` points at `github.com`; parse `owner/repo`
     from both `https://...` and `git@github.com:...` forms.
  4. Local git tag `v<@version>` exists.
  5. No existing GH release for `v<@version>`, unless `--replace`.
  6. Local tarball exists at the expected build path.
- Upload:
  `gh release create v<@version> <tarball> --title "<app> v<@version>" [--draft] [--prerelease]`
- Release notes body is empty in v1; title is auto-generated.
- `--replace` semantics: `gh release delete v<@version> --yes` followed by
  `gh release create ...`. Not atomic; documented.
- Config keys: `draft` (bool), `prerelease` (bool).

### File publisher

- Copies the tarball to a local or mounted directory.
- Preflight checks:
  1. `path` is set and is absolute.
  2. `path` exists and is a writable directory. Do not auto-create.
  3. No file named `<app>-<version>.tar.gz` exists at `path`, unless
     `--replace`.
  4. Local tarball exists at the expected build path.
- Upload: `File.cp!/2` to `<path>/<app>-<version>.tar.gz`.
- `--replace` semantics: overwrite in place.
- Config keys: `path` (absolute dir).

### Publisher contract (internal)

Every publisher implements a small behaviour with exactly two callbacks:

- `preflight(config) :: :ok | {:error, reason}`
- `publish(config, tarball_path, app, version) :: :ok | {:error, reason}`

A type → module dispatch table maps config `type:` values to publisher
modules. Adding a publisher is additive: implement the behaviour, add a
line to the dispatch table, document the config keys.

### Igniter install task

`mix igniter.install release_publisher` must:

- Add `{:release_publisher, "~> x.y", only: [:dev, :test], runtime: false}`
  to `mix.exs` deps.
- Create `config/release_publisher.yml` by delegating to
  `mix release.publish --init`.
- Prompt (not force) the user to add a `release.all` alias:
  `"release.all": ["release", "release.publish"]`.
- Print next steps: edit the config, then run
  `mix release && mix release.publish`.

## Non-Functional Requirements

- **No partial-state surprises.** Preflight for every configured publisher
  runs before any upload begins where possible, so typo'd config fails
  before any network call. (Sequential preflight-then-publish per publisher
  is acceptable if that is simpler; the explicit non-goal is pretending the
  whole run is transactional across publishers.)
- **Clear errors.** Every error message names: which publisher failed
  (including its config identity, e.g. `file[/mnt/releases/myapp]`), which
  step failed, and the minimal fix. No stack traces for user-correctable
  errors.
- **Small dep tree.** Prefer shell-out (`gh`, `git`) over native clients
  where the shell-out is already ubiquitous in the target audience.
- **Stable public contract.** `config/release_publisher.yml`'s location and
  shape are the contract downstream tools depend on; changes need a version
  bump and a note.
- **No library API.** The tool is consumed only via its Mix task.

## Design / UX Notes

- Starter YAML template uses `github` uncommented and `file` commented out,
  so the default `--init` flow produces a file that works for the common
  case after an edit-or-accept.
- Output is plain text, one line per publisher per stage (preflight ok,
  upload ok, done). No progress bars, no color-heavy rendering in v1.
- `--dry-run` output lists, per publisher, exactly what would happen
  ("would upload `<tarball>` to `github:owner/repo` as `v<version>`").

## Technical Approach

- Single Mix task module `Mix.Tasks.Release.Publish`.
- `ReleasePublisher.Config` loads and validates the YAML.
- `ReleasePublisher.Publisher` behaviour + dispatch map.
- `ReleasePublisher.Publishers.Github` and
  `ReleasePublisher.Publishers.File` implement the behaviour.
- `ReleasePublisher.Tarball` computes the expected build path
  (`_build/prod/rel/<app>/<app>-<version>.tar.gz`) and verifies it exists.
- `ReleasePublisher.Git` wraps the `git tag` / `git remote` shell calls.
- Igniter install task lives under
  `Mix.Tasks.ReleasePublisher.Install` (Igniter convention).

## Possible Edge Cases

- Tarball missing → abort with "run `mix release` first".
- `v<@version>` tag missing → abort.
- `gh` not installed or not authed → abort in preflight.
- `origin` remote not on github.com → abort in preflight.
- `gh release` already exists, no `--replace` → abort.
- File publisher `path` missing, not absolute, or not writable → abort
  (do not auto-create).
- File publisher target file already exists, no `--replace` → abort.
- `--only` passed with a type that matches zero configured publishers →
  exit 0 with "no publishers matched" message (do not error).
- Empty or missing `publish:` list → exit 0 with "nothing configured".
- Multiple `file` publishers pointing at the same `path` → each is checked
  independently; second one's preflight will fail after the first writes.
- SSH-form origin URL (`git@github.com:owner/repo.git`) → parsed the same
  as HTTPS form.
- `--replace` on a GH release that is currently a draft or prerelease →
  still deleted and recreated; draft/prerelease flags come from config on
  the new release.

## Acceptance Criteria

- Running `mix release.publish --init` in a fresh project creates
  `config/release_publisher.yml` and exits; running it again refuses to
  overwrite.
- With a valid config and a built tarball, `mix release.publish` uploads
  to every configured publisher in order and reports per-publisher
  success.
- Missing tarball, missing git tag, missing `gh`, bad `origin`, or an
  existing GH release (without `--replace`) each produce an actionable
  error and non-zero exit.
- File publisher refuses to publish to a nonexistent or non-writable
  directory, and refuses to overwrite an existing artifact without
  `--replace`.
- `--replace` causes both publishers to delete and recreate the artifact.
- `--only github` runs only github publishers; `--only file` runs only
  file publishers; `--only` may be repeated.
- `--dry-run` performs preflight and reports planned actions without
  uploading.
- `mix igniter.install release_publisher` leaves the project in a
  committable state with deps updated and a starter config written.
- Downstream `relman`-class tool can read `config/release_publisher.yml`
  and discover publish targets without depending on `release_publisher`
  as a library.

## Open Questions

- **Multi-project repos.** Does a single `config/release_publisher.yml`
  cover all releases in an umbrella, or does each release need its own
  file? v1 assumes one release per project; revisit if a real user hits
  the limit.
- **Credentials for future publishers.** `gh` inherits `gh auth`; future
  `s3`/`scp`/`rsync` publishers will need an answer for credential
  sourcing (env vars, shared config, ...). Not v1, but worth naming.
- **Release notes body.** v1 leaves the body empty. A future revision
  will choose between tag message and `CHANGELOG.md`; deferred until
  more than one real user exists.
- **Running preflight for all publishers before any upload.** The design
  document describes preflight-then-publish per-publisher; consider
  whether a global preflight pass across all publishers before any
  upload begins is worth the complexity. Decide during implementation.

## Out of Scope

- Building the tarball (`mix release` owns that).
- Fetching or downloading published tarballs.
- Deploying, SSH, systemd, remote host management (beyond publishers
  that naturally shell out, which are post-v1 anyway).
- A public Elixir library API; no `Mix.install` scripting use case.
- Managing version numbers or creating git tags (that is `git_ops`' job).
- Release notes sourcing (tag message vs. `CHANGELOG.md`).
- Signing or checksums of published tarballs.
- Publishers beyond `github` and `file` (rsync, scp, s3, http-put are
  explicitly deferred, shape-compatible for later addition).
- A `config.exs`-based config location; YAML only in v1.
- `--init --force` regeneration (decision: no).
- A `tarball_path:` config override (decision: no in v1).
- Cross-publisher transactional rollback.

## Testing Guidelines

Create meaningful tests for the following use cases, without going too heavy:

- Config loader parses a valid YAML with mixed publishers and preserves
  declared order; empty/missing `publish:` produces a zero-publisher
  result, not an error.
- GitHub publisher preflight: each failure mode (`gh` missing, not authed,
  non-github origin, missing tag, existing release without `--replace`,
  missing tarball) returns a distinct error the task formats clearly.
- GitHub publisher parses both HTTPS and SSH `origin` URL forms into
  `owner/repo`.
- File publisher preflight: non-absolute path, missing dir, non-writable
  dir, existing target file without `--replace` each produce distinct
  errors.
- File publisher happy path copies the tarball to
  `<path>/<app>-<version>.tar.gz`.
- `mix release.publish --init` writes the starter template; second run
  refuses to overwrite.
- `--only` filters publishers by type; `--dry-run` performs preflight
  without calling the upload path; `--replace` is threaded through to
  publishers.
- End-to-end task run: given a stubbed tarball, stubbed git tag, and
  stubbed `gh`/`File.cp` boundaries, the task runs all configured
  publishers in order and reports success.
