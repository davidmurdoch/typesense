#!/bin/sh
set -eu
: "${TYPESENSE_PKGREL:?Set the package revision}"
: "${SOURCE_COMMIT:?Set the source commit}"
: "${SOURCE_DATE_EPOCH:?Set the source commit timestamp}"
: "${SOURCE_REPOSITORY:?Set owner/repository}"
[ "$(apk --print-arch)" = x86_64 ]
case "$TYPESENSE_PKGREL" in ''|*[!0-9]*) echo "Invalid package revision" >&2; exit 1;; esac
case "$SOURCE_COMMIT" in *[!0-9a-f]*) echo "Invalid source commit" >&2; exit 1;; esac
[ "${#SOURCE_COMMIT}" -eq 40 ]
case "$SOURCE_DATE_EPOCH" in ''|*[!0-9]*) echo "Invalid source timestamp" >&2; exit 1;; esac
[ -x /input/typesense-server ]
[ -r /run/secrets/typesense-alpine.rsa ]
mkdir -p /work/build /work/packages /work/keys /out
[ -z "$(ls -A /out)" ] || { echo "The output directory must be empty" >&2; exit 1; }
trap 'rm -f /work/keys/typesense-alpine.rsa' EXIT
trap 'exit 1' HUP INT TERM
cp /package/APKBUILD /package/typesense.initd /package/typesense.confd \
    /package/typesense-server.ini /package/typesense.pre-install /package/LICENSE.txt /work/build/
cp /run/secrets/typesense-alpine.rsa /work/keys/typesense-alpine.rsa
chmod 600 /work/keys/typesense-alpine.rsa
openssl pkey -in /work/keys/typesense-alpine.rsa -pubout -out /work/keys/typesense-alpine.rsa.pub
cp /work/keys/typesense-alpine.rsa.pub /etc/apk/keys/
sh /work/build/typesense.pre-install
chown -R builder:builder /work
export TYPESENSE_BINARY=/input/typesense-server
export PACKAGER_PRIVKEY=/work/keys/typesense-alpine.rsa
export PACKAGER="Typesense Alpine packaging"
# The image already contains the runtime dependencies; no root package installation is needed.
su-exec builder abuild -d -C /work/build -P /work/packages
pkgver=$(sed -n 's/^pkgver=//p' /package/APKBUILD)
pkgrel=$TYPESENSE_PKGREL
cp /work/packages/*/x86_64/*.apk /out/
cp /work/keys/typesense-alpine.rsa.pub /out/
# The standard Alpine repositories supply the runtime dependencies.
apk index --no-warnings -o /out/APKINDEX.tar.gz /out/*.apk
abuild-sign -k "$PACKAGER_PRIVKEY" -p typesense-alpine.rsa.pub /out/APKINDEX.tar.gz
binary_sha256=$(sha256sum /input/typesense-server | cut -d' ' -f1)
public_key_sha256=$(sha256sum /out/typesense-alpine.rsa.pub | cut -d' ' -f1)
tag=""
if [ "$pkgrel" != 0 ]; then tag="v$pkgver-alpine.$pkgrel"; fi
jq -n --arg upstream "$pkgver" --arg revision "$pkgrel" --arg tag "$tag" \
    --arg commit "$SOURCE_COMMIT" --arg repository "$SOURCE_REPOSITORY" \
    --arg alpine "$(cat /etc/alpine-release)" --arg binary_sha256 "$binary_sha256" \
    --arg public_key_sha256 "$public_key_sha256" \
    '{upstream_version:$upstream,package_revision:$revision,tag:$tag,commit:$commit,
      repository:$repository,alpine:$alpine,architecture:"x86_64",binary_sha256:$binary_sha256,
      public_key_sha256:$public_key_sha256,
      source_url:("https://github.com/"+$repository+"/archive/"+$commit+".tar.gz")}' > /out/BUILD.json
install -m 0644 /package/LICENSE.txt /out/LICENSE.txt
# Preserve the exact tested executable; compression does not strip or relink it.
archive="/out/typesense-server-$pkgver-alpine.$pkgrel-linux-musl-amd64.tar.gz"
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
    -czf "$archive" -C /input typesense-server -C /out LICENSE.txt BUILD.json
(cd /out && sha256sum -- *.apk APKINDEX.tar.gz BUILD.json LICENSE.txt typesense-alpine.rsa.pub typesense-server-*.tar.gz > SHA256SUMS)
