#!/bin/bash
set -euo pipefail
# shellcheck source=test/alpine_smoke_helpers.sh
source "$(dirname "$0")/alpine_smoke_helpers.sh"
URL=http://127.0.0.1:8108
API_KEY=typesense-package-test-key
package_version=$(jq -r '.upstream_version + "-r" + .package_revision' /repo/BUILD.json)

cleanup() {
    local exit_code=$?
    if ((exit_code != 0)); then
        cat /var/log/typesense-supervisor/stdout.log /var/log/typesense-supervisor/stderr.log 2>/dev/null || true
    fi
    rc-service --nodeps typesense stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

# A flat HTTP repository exercises the same URL layout as GitHub release assets.
httpd -p 127.0.0.1:8080 -h /repo
printf 'ndx @typesense http://127.0.0.1:8080/APKINDEX.tar.gz\n' > /tmp/typesense-repositories
if apk update --no-cache --repositories-file=/tmp/typesense-repositories >/tmp/untrusted.log 2>&1; then
    echo 'The repository was accepted without its signing key' >&2
    exit 1
fi
grep -Ei 'untrusted|signature' /tmp/untrusted.log >/dev/null
install -m 0644 /repo/typesense-alpine.rsa.pub /etc/apk/keys/
apk add --no-cache --repositories-file=/tmp/typesense-repositories \
    "typesense@typesense=$package_version" "typesense-openrc@typesense=$package_version"
expected=$(jq -r .binary_sha256 /repo/BUILD.json)
test "$(sha256sum /usr/bin/typesense-server | cut -d' ' -f1)" = "$expected"
archive=$(find /repo -name 'typesense-server-*.tar.gz')
test "$(tar -xzOf "$archive" typesense-server | sha256sum | cut -d' ' -f1)" = "$expected"
test -z "$(find /repo -name '*.rsa')"
sed -i "s/^api-key =$/api-key = $API_KEY/" /etc/typesense/typesense-server.ini
printf '\nthread-pool-size = 8\nnum-collections-parallel-load = 1\n' >> /etc/typesense/typesense-server.ini
mkdir -p /run/openrc
touch /run/openrc/softlevel
rc-service --nodeps typesense start
ready
request /debug | jq -e --arg version "$(jq -r .upstream_version /repo/BUILD.json)" '.version == $version' >/dev/null
pid() { pgrep -u typesense -f '^/usr/bin/typesense-server( |$)'; }
old_pid=$(pid)
test -n "$old_pid"
test "$(stat -c %u:%g:%a /run/typesense)" = 0:0:750
test "$(stat -c %U:%G:%a /var/log/typesense-supervisor)" = root:typesense:750
test "$(stat -c %U:%G:%a /var/log/typesense-supervisor/stdout.log)" = typesense:typesense:640
(cd /repo && sha256sum -c SHA256SUMS)
create_fixture
check_search

# Reinstalling packages must preserve local configuration, data and the running service.
apk fix --no-cache --reinstall --repositories-file=/tmp/typesense-repositories typesense typesense-openrc
test "$(pid)" = "$old_pid"
grep -Fx "api-key = $API_KEY" /etc/typesense/typesense-server.ini >/dev/null
check_search
rc-service --nodeps typesense restart
ready
check_search

# supervise-daemon must recover the process after an unexpected exit.
old_pid=$(pid)
kill -KILL "$old_pid"
restarted=false
for ((attempt=0; attempt<120; attempt++)); do
    new_pid=$(pid || true)
    if [[ -n "$new_pid" && "$new_pid" != "$old_pid" ]]; then restarted=true; break; fi
    sleep 0.25
done
$restarted
ready
check_search
rc-service --nodeps typesense stop
if pid >/dev/null; then echo 'Typesense did not stop' >&2; exit 1; fi
echo 'Signed APK installation, configuration preservation and OpenRC lifecycle checks passed.'
