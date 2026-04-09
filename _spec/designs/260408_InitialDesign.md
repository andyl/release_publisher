# release_publisher — Initial Design

A small, focused Mix tool whose only job is to **publish an already-built
Elixir release tarball** to one or more artifact stores (GitHub Releases,
a local/mounted filesystem path, etc.).

It does not build. It does not deploy. It does not fetch. It publishes.

## Motivation

This project is the "publish" half of a deliberate split from `relman`.
Relman grew a publish step inside `mix relman.release`, and while the
code was clean, bundling build + publish + deploy behind one tool
obscured the seam between producing an artifact and installing it.

`release_publisher` exists so that:

- **Intent is self-evident.** `mix release.publish` does exactly what
  its name says. `mix help | grep release` tells the whole story:
  `mix release` builds, `mix release.publish` publishes.
- **The tool stays small.** No deploy code, no SSH, no systemd, no
  fetch/download logic, no library API surface. One task, one job.
- **Bundling is trivial.** A consumer project can define a mix alias:

    ```elixir
    aliases: [
      "release.all": ["release", "release.publish"]
    ]
    ```

  …and get the full build+publish cycle with one command, while each
  half remains independently callable.
- **Composes with any deploy tool.** Relman will be the first consumer
  but not the only one. Any deploy tool that knows how to fetch a
  tarball from GitHub Releases (or an NFS share) can consume artifacts
  published by `release_publisher` without knowing this project exists.

Companion projects handle the other concerns: `relman` (or its
successor) handles fetch + deploy + manage. `release_publisher` never needs
to know.

## Scope

### In scope

- A single Mix task: `mix release.publish`.
- A single init flag: `mix release.publish --init`, which writes a
  starter `config/release_publisher.yml`.
- An Igniter `install` task that bootstraps the project (in practice,
  just invokes `--init` plus any small wiring needed).
- Two publishers in v1: `github` and `file`.
- Preflight validation that fails fast *before* any upload begins.
- Idempotency: re-publishing the same version is an error unless the
  user explicitly asks to replace.

### Out of scope

- Building the tarball (`mix release` does that).
- Fetching / downloading published tarballs (a separate tool owns
  that — `release_publisher` is strictly one-way).
- Deploying, SSH, systemd, remote host management.
- A public Elixir library API. `release_publisher` is consumed via its Mix
  task only. No `Mix.install` scripting use case.
- Managing version numbers or creating git tags. That is `git_ops`'
  job (or equivalent). `release.publish` *reads* the tag but does
  not create it.
- Release notes sourcing (tag message vs. `CHANGELOG.md`). v1 uses a
  minimal auto-generated title and empty body; revisit later.
- Signing / checksums of published tarballs.
- Publishers beyond `github` and `file` (see "Future Publishers").

## The Task

### `mix release.publish`

Reads `@version` from `mix.exs`, loads `config/release_publisher.yml`, and
for each configured publisher:

1. Runs the publisher's **preflight** checks. Any failure aborts
   *before* any upload begins — no partial state.
2. Locates the locally built tarball for `@version`. If missing,
   abort with a clear message telling the user to run `mix release`
   first. `release_publisher` never builds.
3. Verifies the local git tag `v<@version>` exists. If missing,
   abort — `release_publisher` will not publish unversioned artifacts.
4. Invokes the publisher's **upload** action.
5. Reports success per publisher.

Publishers run sequentially in the order declared in config. The
first publisher error stops the run; already-completed publishers
are not rolled back (uploads are not transactional, and pretending
otherwise would be a lie).

**Flags:**

| Flag            | Effect                                                                  |
|-----------------|-------------------------------------------------------------------------|
| `--init`        | Write a starter `config/release_publisher.yml` and exit. No publish.          |
| `--replace`     | If the artifact already exists at the target, delete and recreate it.   |
| `--only <type>` | Run only publishers of a given type (e.g. `--only github`). Repeatable. |
| `--dry-run`     | Run preflight + report what *would* be published. No upload.            |

No `--force` flag, because there is no build step to force. No
`--from-release`, because there is no fetch. Staying small.

### `mix release.publish --init`

Writes `config/release_publisher.yml` with a commented-out template
containing the full publisher shape. If the file already exists,
refuses to overwrite and points the user at the existing file.

Starter template:

```yaml
# release_publisher config
# Each entry under `publish:` is a publisher. Publishers run
# sequentially in declared order. Remove or comment out anything
# you don't need.

publish:
  - type: github
    draft: false
    prerelease: false

  # - type: file
  #   path: /mnt/releases/myapp/
```

### Igniter `install` Task

`mix igniter.install release_publisher` should leave the project in a
working, committable state:

- Adds `{:release_publisher, "~> x.y", only: [:dev, :test], runtime: false}` to `mix.exs` deps (Igniter standard).
- Creates `config/release_publisher.yml` by delegating to
  `mix release.publish --init`.
- Optionally adds a `release.all` alias (see Motivation) — **prompted,
  not forced.** The user may already have their own alias scheme.
- Prints next steps: "edit `config/release_publisher.yml`, then run
  `mix release && mix release.publish`."

If there is any doubt about what Igniter should touch beyond the
config file, prefer doing less. The rest is documentation.

## Config Shape

File: `config/release_publisher.yml` (YAML, not `config.exs`, for v1).

Rationale for YAML over `config.exs`:
- Matches `relman.yml` convention, so a project using both tools has
  two similar-shaped files in `config/`.
- Easier for tooling (including this one's `--init`) to read/write.
- Plays nicer with operators who may edit publishing targets without
  touching Elixir code.

Future: once the schema stabilizes, `config/config.exs` becomes a
second supported location. Not in v1.

**Shape:**

```yaml
publish:
  - type: github
    draft: false
    prerelease: false

  - type: file
    path: /mnt/releases/myapp/
```

`publish:` is a list, not a map, so publisher order is explicit and
the same type can appear more than once (e.g. two `file` targets,
one local archive and one NFS share).

Omitting `publish:` or leaving it empty → `mix release.publish`
exits 0 with a "nothing configured" message. Not an error.

### Config discovery by other tools

A deploy tool (`relman` or successor) may want to read
`config/release_publisher.yml` to discover where tarballs were published,
so it knows where to fetch from. This is explicitly allowed: the
file's location and shape are stable public contracts for exactly
this purpose. `release_publisher` itself, however, never reads config
from any other tool.

## Publisher Contract

Internally, every publisher implements a tiny behaviour:

```elixir
@callback preflight(config :: map) :: :ok | {:error, reason :: term}
@callback publish(config :: map, tarball_path :: Path.t,
                  app :: String.t, version :: String.t) ::
            :ok | {:error, reason :: term}
```

Two callbacks, not three — no `fetch`, because `release_publisher` is
one-way. This keeps `mix release.publish` free of per-publisher
branching and makes adding a new publisher a matter of implementing
the behaviour plus a line in the type→module dispatch table.

## GitHub Publisher

Uses the `gh` CLI rather than a native HTTP client. `gh` handles
auth, retries, and multipart upload, and any project that already
publishes to GitHub almost certainly has `gh` installed.

**Preflight checks** (fail fast, in order):

1. `gh` executable is on `$PATH`.
2. `gh auth status` exits 0.
3. `git remote get-url origin` points at `github.com`. Parse
   `owner/repo` from the URL (support both `https://...` and
   `git@github.com:...` forms).
4. Local git tag `v<@version>` exists.
5. No existing GH release for `v<@version>` — unless `--replace`
   was passed, in which case the existing release will be deleted
   and recreated.
6. Local tarball exists at the expected path
   (`_build/prod/rel/<app>/<app>-<version>.tar.gz`).

**Upload:**

```
gh release create v<@version> <tarball> \
    --title "<app> v<@version>" \
    [--draft] [--prerelease]
```

Release notes body is empty in v1. Title is auto-generated. A future
revision will choose between tag message and `CHANGELOG.md`; that
decision is deferred until we have more than one real user.

**Replace semantics** (`--replace`): `gh release delete v<@version>
--yes` followed by `gh release create ...`. Not atomic, but GH has
no atomic replace; this is the standard dance.

## File Publisher

Copies the tarball to a local or mounted directory. Useful for NFS
shares, directories fronted by a static web server, or a plain
local archive folder.

**Config:**

```yaml
- type: file
  path: /mnt/releases/myapp/
```

**Preflight checks:**

1. `path` is set and is an absolute path.
2. `path` exists and is a writable directory. **Do not auto-create.**
   Failing loudly on a typo'd path is better than silently creating
   one.
3. No file named `<app>-<version>.tar.gz` already exists at `path`
   — unless `--replace` was passed.
4. Local tarball exists at the expected build path.

**Upload:** `File.cp!/2` to `<path>/<app>-<version>.tar.gz`. That is
the entire implementation. The trivial publisher stays trivial.

**Replace semantics** (`--replace`): overwrite in place.

## Idempotency

Re-running `mix release.publish` for the same `@version`:

- With no flags: errors on the first publisher whose artifact
  already exists. Exit non-zero. No partial publish beyond whatever
  succeeded before the conflict (document this; don't pretend it's
  transactional).
- With `--replace`: each publisher deletes its existing artifact
  and uploads the new one.

The assumption is that republishing the same version is almost
always a mistake (you meant to bump the version first). Making the
safe path the default path matters more than convenience here.

## Typical Flows

**One-shot release cycle:**

```
mix git_ops.release       # bump version, create v<x.y.z> tag
mix release               # build the tarball
mix release.publish       # upload to all configured publishers
```

**Bundled via alias** (recommended for most projects):

```elixir
# mix.exs
aliases: [
  "release.all": ["release", "release.publish"]
]
```

```
mix git_ops.release
mix release.all
```

**Publish only to one target** (e.g. quick local-only publish while
debugging a GH issue):

```
mix release.publish --only file
```

**Re-publish after a botched upload** (and you're sure you want to):

```
mix release.publish --replace
```

## Error Reporting

Every error message should name:

1. **Which publisher** failed (`github`, `file[/mnt/releases/myapp]`).
2. **Which check or step** failed (preflight step N, upload, replace).
3. **The minimal fix** — "run `gh auth login`", "create
   `/mnt/releases/myapp` as a writable directory", "pass `--replace`
   to overwrite", etc.

No stack traces for user-correctable errors. Stack traces only for
genuine bugs in `release_publisher` itself.

## Future Publishers

Deliberately out of v1 but shape-compatible for future addition:

- **rsync** — `rsync <tarball> user@host:/path/`. Preflight checks
  SSH reachability and remote writability.
- **scp** — similar, using `scp` rather than `rsync`.
- **s3** — via `aws s3 cp` (shell-out, matching the `gh` pattern) or
  via `ex_aws_s3` (native). Preferred choice TBD; shell-out keeps
  the dep tree small.
- **http-put** — generic PUT to a presigned URL.

Each additional publisher is purely additive: implement the two
behaviour callbacks, register it in the type dispatch, document
the config keys. No changes to `mix release.publish` itself.

## Open Questions

- **Multi-project repos.** If a single repo builds multiple releases
  (umbrella apps with multiple releases defined), does one
  `config/release_publisher.yml` cover all of them, or does each release
  need its own file? v1 assumes one release per project. Revisit if
  someone hits this.
- **Credentials for non-`gh` publishers.** The `gh` publisher
  inherits whatever `gh auth` has. Future `s3` / `scp` publishers
  will need an answer for where credentials come from (env vars,
  shared config, etc.). Not v1 territory but worth naming.
- **`--init` regeneration.** Should `--init --force` be supported for
  rewriting an existing config? Leaning no: if the user wants a
  fresh template, deleting the file is one command and makes intent
  obvious.  Answer: no 
- **Tarball path override.** Currently the build path is computed
  from conventions. Should config allow an explicit
  `tarball_path:` override for projects with non-standard build
  layouts? Probably yes eventually, no in v1.  Answer: no in V1.
