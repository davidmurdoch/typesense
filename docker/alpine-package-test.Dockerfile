# syntax=docker/dockerfile:1
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN --mount=type=secret,id=ca_bundle \
    set -eu; \
    if [ -f /run/secrets/ca_bundle ]; then export SSL_CERT_FILE=/run/secrets/ca_bundle; fi; \
    apk add --no-cache bash openrc curl jq gdb busybox-extras ca-certificates \
        libgcc libstdc++ libunwind musl-fts musl-obstack libcrypto3 libssl3 libcurl zlib=1.4-r0 icu-libs icu-data-full
COPY test/alpine_package_smoke.sh test/alpine_smoke_helpers.sh /tests/
ENTRYPOINT ["/bin/bash", "/tests/alpine_package_smoke.sh"]
