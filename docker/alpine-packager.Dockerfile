# syntax=docker/dockerfile:1
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN --mount=type=secret,id=ca_bundle \
    set -eu; \
    if [ -f /run/secrets/ca_bundle ]; then export SSL_CERT_FILE=/run/secrets/ca_bundle; fi; \
    apk add --no-cache abuild openssl su-exec jq tar ca-certificates libgcc libunwind musl-fts musl-obstack; \
    adduser -D builder; \
    addgroup builder abuild

COPY LICENSE.txt packaging/alpine/APKBUILD packaging/alpine/package.sh \
    packaging/alpine/typesense.pre-install packaging/alpine/typesense.initd \
    packaging/alpine/typesense.confd packaging/alpine/typesense-server.ini /package/
ENTRYPOINT ["/bin/sh", "/package/package.sh"]
