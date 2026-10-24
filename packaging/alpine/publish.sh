#!/bin/bash
set -euo pipefail
tag=${1:?Usage: publish.sh TAG COMMIT ASSET_DIRECTORY}
commit=${2:?Set the tested commit}
assets=$(cd "${3:?Set the asset directory}" && pwd)
: "${GITHUB_REPOSITORY:?Set owner/repository}"
root=$(cd "$(dirname "$0")/../.." && pwd)
upstream=$(sed -n 's/^pkgver=//p' "$root/packaging/alpine/APKBUILD")
pattern="^v${upstream//./\\.}-alpine\\.([1-9][0-9]*)$"
[[ "$tag" =~ $pattern ]] || { echo "Invalid Alpine release tag" >&2; exit 1; }
revision=${BASH_REMATCH[1]}
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid commit" >&2; exit 1; }
jq -e --arg tag "$tag" --arg commit "$commit" --arg repository "$GITHUB_REPOSITORY" \
    --arg version "$upstream" --arg revision "$revision" \
    '.tag == $tag and .commit == $commit and .repository == $repository and
     .upstream_version == $version and .package_revision == $revision and .architecture == "x86_64"' \
    "$assets/BUILD.json" >/dev/null
files=("$assets"/typesense-"$upstream"-r"$revision".apk
       "$assets"/typesense-openrc-"$upstream"-r"$revision".apk
       "$assets"/typesense-server-"$upstream"-alpine."$revision"-linux-musl-amd64.tar.gz
       "$assets"/APKINDEX.tar.gz "$assets"/BUILD.json "$assets"/LICENSE.txt
       "$assets"/typesense-alpine.rsa.pub "$assets"/SHA256SUMS)
for file in "${files[@]}"; do test -f "$file"; done
expected_files=$(printf '%s\n' "${files[@]##*/}" | grep -v '^SHA256SUMS$' | sort)
manifest_files=$(awk '{print $2}' "$assets/SHA256SUMS" | sort)
[[ "$manifest_files" = "$expected_files" ]] || { echo "The checksum manifest must cover exactly the release assets" >&2; exit 1; }
(cd "$assets" && sha256sum --check --strict SHA256SUMS)
verify_tag() {
    [[ "$(gh api "repos/$GITHUB_REPOSITORY/commits/$tag" --jq .sha)" = "$commit" ]] || {
        echo "The remote tag no longer points to the tested commit" >&2; exit 1;
    }
}
verify_tag

# The standard GNU/Linux suite must also pass for this exact source revision.
deadline=$((SECONDS + 5400))
while true; do
    runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/tests.yml/runs?head_sha=$commit&event=push&per_page=100")
    if jq -e '.workflow_runs | any(.conclusion == "success")' <<< "$runs" >/dev/null; then break; fi
    if jq -e '.workflow_runs | length > 0 and all(.status == "completed")' <<< "$runs" >/dev/null; then
        echo "tests.yml has not passed for $commit; rerun its failed jobs before retrying publication" >&2
        exit 1
    fi
    ((SECONDS < deadline)) || { echo "Timed out waiting for tests.yml on $commit" >&2; exit 1; }
    echo "Waiting for tests.yml on $commit"
    sleep 20
done

verify_tag
state=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
    --jq ".[] | select(.tag_name == \"$tag\") | .draft")
if [[ "$state" == false ]]; then
    echo "Release $tag is already published; published releases are never overwritten" >&2
    exit 1
fi
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
Native Typesense $upstream CPU packages for Alpine Linux 3.24 x86-64, packaging revision $revision.

Source commit: $commit

[Installation and upgrade instructions](https://github.com/$GITHUB_REPOSITORY/blob/$commit/packaging/alpine/README.md)

BUILD.json records source and binary identity; SHA256SUMS covers the release assets.
EOF
if [[ -z "$state" ]]; then
    gh release create "$tag" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
        --title "Typesense $upstream — Alpine revision $revision" --notes-file "$notes"
fi

gh release upload "$tag" --repo "$GITHUB_REPOSITORY" --clobber "${files[@]}"
# Recheck after upload as well: the tag may have changed while checks or uploads ran.
verify_tag
# All assets are in place before publication locks an immutable release.
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft=false
