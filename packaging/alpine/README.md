# Alpine releases and installation

These packages target **Alpine Linux 3.24, x86-64**, with APK 3. The server is a
native musl executable. The `typesense` package contains the server and its
runtime dependencies; `typesense-openrc` adds service management. Other Alpine
branches, architectures and CUDA builds are outside this release workflow.

## Release contents

Each `v30.2-alpine.N` release is a signed repository snapshot hosted entirely as
GitHub Release assets:

- `typesense-30.2-rN.apk` and `typesense-openrc-30.2-rN.apk`.
- `APKINDEX.tar.gz`, signed with the same persistent key as the packages.
- `typesense-alpine.rsa.pub`, the public verification key.
- `typesense-server-30.2-alpine.N-linux-musl-amd64.tar.gz`, the tested executable,
  project license and build metadata.
- `BUILD.json`, recording the source commit, upstream version, package revision,
  target platform, binary checksum and public-key fingerprint.
- `LICENSE.txt` and `SHA256SUMS`.

The upstream server version remains `30.2`; `N` is the downstream packaging
revision. Revision zero is reserved for unpublished CI candidates, which use a
disposable signing key. Published revisions start at one and are never replaced.

## Install from a GitHub Release

Run the installation commands as root. Replace the example release/version when
selecting another release. The release must have completed publication first.

Provision the signing public key once. The release signing key's approved SHA-256
fingerprint is recorded in [signing-key.sha256](signing-key.sha256) and used below.
Keep this fingerprint in your deployment configuration; a checksum downloaded
beside an unfamiliar key does not establish that key's identity.

```sh
apk add ca-certificates curl
REPOSITORY=davidmurdoch/typesense
RELEASE=v30.2-alpine.1
BASE="https://github.com/$REPOSITORY/releases/download/$RELEASE"
KEY_SHA256='3425df422947a4cd24b688c5b69955d86107b442a30fc2de823c5e0a699f5ed6'

(
  set -eu
  KEY_FILE=$(mktemp)
  trap 'rm -f "$KEY_FILE"' EXIT
  curl --fail --location "$BASE/typesense-alpine.rsa.pub" -o "$KEY_FILE"
  printf '%s  %s\n' "$KEY_SHA256" "$KEY_FILE" | sha256sum -c -
  install -m 0644 "$KEY_FILE" /etc/apk/keys/typesense-alpine.rsa.pub
)
```

Add the release's index as a tagged repository and pin both package versions:

```sh
mkdir -p /etc/apk/repositories.d
printf 'ndx @typesense %s/APKINDEX.tar.gz\n' "$BASE" > /etc/apk/repositories.d/typesense.list
apk update
apk add 'typesense@typesense=30.2-r1' 'typesense-openrc@typesense=30.2-r1'
```

APK 3's `ndx` mode reads the index at that exact URL and retrieves packages beside
it; it does not require architecture subdirectories. The repository tag limits
use of this package source to explicitly selected packages. Alpine's normal
repositories provide the runtime libraries. Keep those repositories on the same
Alpine 3.24 branch. Older APK 2 clients cannot use this direct-index configuration.

The package creates a `typesense` service account and leaves the service stopped.
Edit `/etc/typesense/typesense-server.ini`, set a unique nonempty API key, and
choose the API address needed by your clients. Its default address is
`127.0.0.1`. Keep this file owned by `root:typesense`, mode `0640`; keep credentials
and machine-specific configuration outside release artifacts.

```sh
vi /etc/typesense/typesense-server.ini
rc-update add typesense default
rc-service typesense start
curl --fail http://127.0.0.1:8108/health
```

OpenRC runs the process as `typesense`, supervises unexpected exits and stops it
gracefully. Data lives in `/var/lib/typesense`; logs live in `/var/log/typesense`.
The service creates those directories with the service account's ownership.
Supervisor PID files and captured stdout/stderr use root-owned directories under
`/run/typesense` and `/var/log/typesense-supervisor`, respectively.
`/etc/conf.d/typesense` selects an alternative configuration file if needed.
When choosing other data/log directories, create them with appropriate service
account permissions before starting the service.

## Upgrade and recovery

Keep the release URL and exact APK version in your VM configuration. A versioned
release is a fixed snapshot: ordinary system upgrades do not select a newer
Typesense release. Promote a new revision through a staging VM before updating
production, and update clustered nodes one at a time according to the upstream
version's upgrade instructions.

Before changing the selected version, create a backup with the
[Typesense Snapshot API](https://typesense.org/docs/guide/backups.html). A copy of
a running server's live data directory is not a consistent backup.

To install a reviewed revision, update `BASE`, the repository entry and both
version constraints, then stop the service, install and start it again:

```sh
RELEASE=v30.2-alpine.2
BASE="https://github.com/davidmurdoch/typesense/releases/download/$RELEASE"
printf 'ndx @typesense %s/APKINDEX.tar.gz\n' "$BASE" > /etc/apk/repositories.d/typesense.list
rc-service typesense stop
apk update
apk add 'typesense@typesense=30.2-r2' 'typesense-openrc@typesense=30.2-r2'
rc-service typesense start
curl --fail http://127.0.0.1:8108/health
```

Check representative application searches before promoting the revision. APK
preserves locally modified configuration files; inspect any `.apk-new` files
when defaults change. Package installation does not automatically restart a
running server. Stop and disable the OpenRC service before removing its
packages; package removal does not delete the data directory.

An older release remains available at its original URL. Before downgrading,
check Typesense's version-specific compatibility rules: replacing the executable
alone does not reverse data-format migrations. Retain the pre-upgrade snapshot
and matching configuration for recovery.

## Configure release signing once

The current workflow expects the complete private PEM key in the **repository
Actions secret** `APK_SIGNING_KEY`. It derives the public key and checks it against
`signing-key.sha256` before signing a release; a missing or different key fails
the build. Environment secrets require configuring an environment on the job.
Branch and PR builds continue to use disposable keys.

For initial setup on a new fork, a repository maintainer creates and retains a
signing key outside the checkout. If a signing key already exists, retain it
rather than generating a replacement:

```sh
KEY_DIR="$HOME/.config/typesense-release"
install -d -m 0700 "$KEY_DIR"
(umask 077; openssl genrsa -out "$KEY_DIR/typesense-alpine.rsa" 4096)
openssl pkey -in "$KEY_DIR/typesense-alpine.rsa" -pubout -out "$KEY_DIR/typesense-alpine.rsa.pub"
sha256sum "$KEY_DIR/typesense-alpine.rsa.pub"
gh secret set APK_SIGNING_KEY --repo davidmurdoch/typesense < "$KEY_DIR/typesense-alpine.rsa"
```

`APK_SIGNING_KEY` contains the complete PEM private key. Retain a secure backup
and use the same key across releases. Provision the public key and its fingerprint
to VM administrators. For an intentional key rotation, update `signing-key.sha256`
and the fingerprint in the installation commands through review, and distribute
the new trusted public key before consuming releases signed by it. Never commit
a private key.

Enable [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
in the repository settings to lock the assets and tag on publication. The
workflow itself also refuses to overwrite an already-published release.

## Publish a reviewed revision

Update `pkgver` in `APKBUILD` when changing the upstream version. Select a
reviewed commit containing the release workflow, then create an annotated tag
with a new positive packaging revision:

```sh
TAG=v30.2-alpine.1
COMMIT='<full reviewed commit SHA>'
git tag -a "$TAG" "$COMMIT" -m "Typesense 30.2 Alpine revision 1"
git push https://github.com/davidmurdoch/typesense.git "refs/tags/$TAG"
```

The `alpine` workflow builds the native server, runs portability and runtime
checks, signs packages and the index, then installs them from a flat HTTP
repository in a clean Alpine container. It checks signature rejection before
key enrollment, exact binary identity, search and persistence, configuration
preservation during package reinstall, OpenRC restart and crash recovery.

Publication additionally requires a successful push-triggered `tests.yml` run
for that exact source commit, including its GNU/Linux C++ and API jobs. It can
reuse an existing successful run or wait up to 90 minutes for one to complete.
It verifies asset checksums, source metadata and the remote tag before creating
a draft, uploading all assets and publishing it. No second binary build occurs
between testing and publication. The publication job alone receives release-write
permissions; branch and PR checks publish nothing and use disposable keys.

If a run fails, fix or rerun the failed checks, then rerun the tag's workflow.
An existing draft can resume asset upload. A published release is never clobbered;
use a new packaging revision for a correction.

## Local validation

Build the native executable using [the Alpine build instructions](../../docker/ALPINE.md).
Build the package tools and create a disposable test signing key outside the
checkout. `dist/alpine-release` must be empty; preserve any earlier candidate in
another directory before packaging a new one:

```sh
docker build -f docker/alpine-packager.Dockerfile -t typesense-alpine-packager .
TEST_KEY_DIR=$(mktemp -d)
(umask 077; openssl genrsa -out "$TEST_KEY_DIR/typesense-alpine.rsa" 4096)
mkdir -p dist/alpine-release
TYPESENSE_PKGREL=0
SOURCE_COMMIT=$(git rev-parse HEAD)
SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)
SOURCE_REPOSITORY=davidmurdoch/typesense
export TYPESENSE_PKGREL SOURCE_COMMIT SOURCE_DATE_EPOCH SOURCE_REPOSITORY

docker run --rm \
  --mount "type=bind,src=$PWD/dist/typesense-server,dst=/input/typesense-server,readonly" \
  --mount "type=bind,src=$PWD/dist/alpine-release,dst=/out" \
  --mount "type=bind,src=$TEST_KEY_DIR/typesense-alpine.rsa,dst=/run/secrets/typesense-alpine.rsa,readonly" \
  -e TYPESENSE_PKGREL -e SOURCE_COMMIT -e SOURCE_DATE_EPOCH -e SOURCE_REPOSITORY \
  typesense-alpine-packager

docker build -f docker/alpine-package-test.Dockerfile -t typesense-alpine-package-test .
docker run --rm --cpus=1 --memory=512m --memory-swap=512m \
  --mount "type=bind,src=$PWD/dist/alpine-release,dst=/repo,readonly" \
  typesense-alpine-package-test
python3 -B -m unittest discover -s test -p alpine_release_workflow_test.py
rm "$TEST_KEY_DIR/typesense-alpine.rsa"
rmdir "$TEST_KEY_DIR"
```

Use a disposable key for local validation; its public key is not a production
trust anchor. Build networks needing an additional CA can pass the Dockerfiles'
optional `ca_bundle` BuildKit secret as described in the build instructions.
