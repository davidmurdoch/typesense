#!/bin/bash
set -euo pipefail

IMAGE=${1:-typesense-alpine-runtime:test}
CONTAINER="typesense-alpine-test-$RANDOM-$$"
VOLUME="$CONTAINER-data"
API_KEY=typesense-test-key
# shellcheck source=test/alpine_smoke_helpers.sh
source "$(dirname "$0")/alpine_smoke_helpers.sh"
created=false
volume_created=false

cleanup() {
  local exit_code=$?
  if $created; then
    if ((exit_code != 0)); then docker logs "$CONTAINER" || true; fi
    docker rm --force "$CONTAINER" >/dev/null
  fi
  if $volume_created; then
    docker volume rm "$VOLUME" >/dev/null
  fi
}
trap cleanup EXIT

docker volume create "$VOLUME" >/dev/null
volume_created=true
docker run -d --name "$CONTAINER" --cpus=1 --memory=384m --memory-swap=384m \
  -p 127.0.0.1::8108 --mount "type=volume,src=$VOLUME,dst=/var/lib/typesense" \
  "$IMAGE" --data-dir=/var/lib/typesense --api-key="$API_KEY" \
  --api-address=0.0.0.0 --thread-pool-size=8 --num-collections-parallel-load=1 >/dev/null
created=true
URL="http://$(docker port "$CONTAINER" 8108/tcp)"


ready
test "$(docker exec "$CONTAINER" id -u)" != 0
docker exec "$CONTAINER" sh -c '
  for tool in gcc g++ cmake bazel; do
    if command -v "$tool" >/dev/null; then exit 1; fi
  done
  test ! -e /lib/ld-linux-x86-64.so.2
'
create_fixture
check_search

docker stop --timeout=30 "$CONTAINER" >/dev/null
test "$(docker inspect --format '{{.State.OOMKilled}} {{.State.ExitCode}}' "$CONTAINER")" = 'false 0'
docker start "$CONTAINER" >/dev/null
URL="http://$(docker port "$CONTAINER" 8108/tcp)"
ready
check_search
echo 'Alpine runtime import, search and persistence checks passed.'
