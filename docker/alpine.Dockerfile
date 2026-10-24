# syntax=docker/dockerfile:1
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN --mount=type=secret,id=ca_bundle \
    set -eu; \
    if [ -f /run/secrets/ca_bundle ]; then export SSL_CERT_FILE=/run/secrets/ca_bundle; fi; \
    apk add --no-cache ca-certificates libgcc libunwind musl-fts musl-obstack; \
    addgroup -S -g 1000 typesense; \
    adduser -S -D -H -u 1000 -G typesense typesense; \
    mkdir -p /var/lib/typesense; \
    chown typesense:typesense /var/lib/typesense

COPY typesense-server /opt/typesense-server
USER typesense
EXPOSE 8108
STOPSIGNAL SIGINT
ENTRYPOINT ["/opt/typesense-server"]
