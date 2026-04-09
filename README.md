# ReleasePublisher

A small, focused Mix tool whose only job is to **publish an already-built
Elixir release tarball** to one or more artifact stores (GitHub Releases,
a local or mounted filesystem path, etc.).

It does not build. It does not deploy. It does not fetch. It publishes.

`release_publisher` is the "publish" half of a deliberate split from
`relman`: `mix release` builds the tarball, `mix release.publish` uploads
it, and a separate deploy tool fetches and installs it. Each half stays
independently callable and trivially composable.

## Installation

Add `release_publisher` to the `deps` list in your `mix.exs`. It is a
dev/test tool — mark it `runtime: false` so it never ships with your
release:

```elixir
def deps do
  [
    {:release_publisher, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

Then either run the Igniter installer:

```
mix igniter.install release_publisher
```

…or bootstrap the config by hand:

```
mix release.publish --init
```

Either approach creates `config/release_publisher.yml` with a starter
template you can edit.

## Usage

The typical one-shot release cycle:

```
mix git_ops.release       # bump version, create v<x.y.z> tag
mix release               # build the tarball
mix release.publish       # upload to all configured publishers
```

Most projects will want to bundle build + publish behind a single alias:

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

### Flags

| Flag                   | Effect                                                                  |
|------------------------|-------------------------------------------------------------------------|
| `--init`               | Write a starter `config/release_publisher.yml` and exit. No publish.    |
| `--replace`            | If the artifact already exists at the target, delete and recreate it.   |
| `--only <type>`        | Run only publishers of a given type. Repeatable, or comma-separated (e.g. `--only github,file`). |
| `--dry-run`            | Run preflight and report what would be published. No upload.           |

There is deliberately no `--force` (no build step to force) and no
`--from-release` (no fetch). Staying small.

## Configuration

`release_publisher` reads `config/release_publisher.yml`. The file is a
stable public contract — downstream deploy tools are expected to read
this file directly to discover where tarballs were published. YAML (not
`config.exs`) so operators can edit publishing targets without touching
Elixir code, and so the same shape matches `relman.yml`.

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

`publish:` is an ordered list, not a map, so publisher order is explicit
and the same type can appear more than once (e.g. two `file` targets —
one local archive and one NFS share). Omitting or emptying `publish:` is
not an error: `mix release.publish` exits 0 with a "nothing configured"
message.

## Publishers

v1 ships two publishers.

### `github`

Shells out to the [`gh`](https://cli.github.com/) CLI, which handles
auth, retries, and multipart upload. Any project that already publishes
to GitHub almost certainly has `gh` installed.

```yaml
- type: github
  draft: false
  prerelease: false
```

Upload is equivalent to:

```
gh release create v<version> <tarball> \
    --title "<app> v<version>" \
    [--draft] [--prerelease]
```

Release notes body is empty in v1; title is auto-generated. Replacing an
existing release (`--replace`) runs `gh release delete v<version> --yes`
followed by `gh release create ...`. Not atomic — GitHub has no atomic
replace — but it is the standard dance.

### `file`

Copies the tarball to a local or mounted directory. Useful for NFS
shares, directories fronted by a static web server, or a plain local
archive folder.

```yaml
- type: file
  path: /mnt/releases/myapp/
```

The target directory must already exist and be writable —
`release_publisher` never auto-creates it. Failing loudly on a typo'd
path is better than silently creating one.

## Preflight and error reporting

Before any upload begins, `release_publisher` runs a global preflight
pass across every configured publisher. If any publisher's preflight
fails, the whole run aborts before a single byte has been uploaded — no
partial state from typo'd config.

Preflight checks include, for the `github` publisher:

1. `gh` is on `$PATH`.
2. `gh auth status` exits 0.
3. `git remote get-url origin` points at `github.com` (HTTPS or SSH form).
4. Local git tag `v<version>` exists.
5. No existing GitHub release for `v<version>`, unless `--replace`.
6. Local tarball exists at the expected build path.

And for the `file` publisher:

1. `path` is set and absolute.
2. `path` exists and is a writable directory.
3. No file named `<app>-<version>.tar.gz` already exists at `path`,
   unless `--replace`.
4. Local tarball exists at the expected build path.

Every error message names which publisher failed, which step failed,
and the minimal fix — "run `gh auth login`", "create
`/mnt/releases/myapp` as a writable directory", "pass `--replace` to
overwrite". No stack traces for user-correctable errors.

## Idempotency

Re-running `mix release.publish` for the same version errors out on the
first publisher whose artifact already exists. The assumption is that
republishing the same version is almost always a mistake — you meant to
bump the version first. Pass `--replace` when you really mean it:

```
mix release.publish --replace
```

`--replace` is not transactional across publishers; already-completed
publishers are not rolled back if a later one fails. Uploads are not
transactional, and `release_publisher` will not pretend otherwise.

## What `release_publisher` does not do

- **Build the tarball.** `mix release` owns that.
- **Fetch or download published tarballs.** A separate tool owns that —
  `release_publisher` is strictly one-way.
- **Deploy.** No SSH, no systemd, no remote host management.
- **Create git tags or manage version numbers.** That is `git_ops`' job.
  `mix release.publish` reads the tag but does not create it.
- **Provide a public Elixir library API.** The tool is consumed only
  via its Mix task. No `Mix.install` scripting use case.
- **Sign or checksum tarballs.** Not in v1.
