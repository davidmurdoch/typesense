#!/bin/bash
# Shared HTTP checks for the runtime image and native APK service.

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

create_fixture() {
  request /collections -X POST --data \
    '{"name":"portability","fields":[{"name":"name","type":"string"}]}' >/dev/null
  request '/collections/portability/documents/import?action=create' -X POST --data-binary \
    $'{"id":"banana","name":"Banana"}\n{"id":"cafe","name":"Café latte"}\n{"id":"chicken","name":"Chicken breast raw"}' \
    | jq -se 'length == 3 and all(.[]; .success)' >/dev/null
}
