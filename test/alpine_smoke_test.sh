#!/bin/bash
set -euo pipefail

IMAGE=${1:-typesense-alpine-runtime:test}
CONTAINER="typesense-alpine-test-$RANDOM-$$"
VOLUME="$CONTAINER-data"
API_KEY=typesense-test-key
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

ready() {
  for ((attempt=0; attempt<120; attempt++)); do
    if curl --silent --fail --max-time 1 "$URL/health" | jq -e '.ok == true' >/dev/null; then
      return
    fi
    sleep 0.25
  done
  echo 'Typesense did not become ready' >&2
  return 1
}

request() {
  local path=$1
  shift
  curl --silent --show-error --fail -H "X-TYPESENSE-API-KEY: $API_KEY" \
    -H 'Content-Type: application/json' "$@" "$URL$path"
}

check_search() {
  request /collections/portability | jq -e '.num_documents == 3' >/dev/null
  request /multi_search -X POST --data \
    '{"searches":[{"collection":"portability","q":"bananna","query_by":"name"},{"collection":"portability","q":"cafe","query_by":"name"}]}' \
    | jq -e '.results[0].hits[0].document.id == "banana" and .results[1].hits[0].document.id == "cafe"' >/dev/null
}

ready
test "$(docker exec "$CONTAINER" id -u)" != 0
docker exec "$CONTAINER" sh -c '
  for tool in gcc g++ cmake bazel; do
    if command -v "$tool" >/dev/null; then exit 1; fi
  done
  test ! -e /lib/ld-linux-x86-64.so.2
'
request /collections -X POST --data \
  '{"name":"portability","fields":[{"name":"name","type":"string"}]}' >/dev/null
request '/collections/portability/documents/import?action=create' -X POST --data-binary \
  $'{"id":"banana","name":"Banana"}\n{"id":"cafe","name":"Café latte"}\n{"id":"chicken","name":"Chicken breast raw"}' \
  | jq -se 'length == 3 and all(.[]; .success)' >/dev/null
check_search

docker stop --timeout=30 "$CONTAINER" >/dev/null
test "$(docker inspect --format '{{.State.OOMKilled}} {{.State.ExitCode}}' "$CONTAINER")" = 'false 0'
docker start "$CONTAINER" >/dev/null
URL="http://$(docker port "$CONTAINER" 8108/tcp)"
ready
check_search
echo 'Alpine runtime import, search and persistence checks passed.'
