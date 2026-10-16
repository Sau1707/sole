#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
temp_root=${TMPDIR:-/tmp}
if [ -z "${TMPDIR:-}" ] && [ -d /tmp/opencode ]; then temp_root=/tmp/opencode; fi
temporary=$(mktemp -d "$temp_root/sole-release-test-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

archive=sole-0.0.0-linux-x86_64
sh "$root/install.sh" "$temporary/$archive" > "$temporary/log"
mkdir "$temporary/downloads" "$temporary/tools"
tar -C "$temporary" -czf "$temporary/downloads/$archive.tar.gz" "$archive"
(cd "$temporary/downloads" && sha256sum "$archive.tar.gz" > SHA256SUMS)
cat > "$temporary/tools/curl" <<'EOF'
#!/bin/sh
set -eu
file=
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        https://*) file=${1##*/} ;;
        -o) shift; output=$1 ;;
    esac
    shift
done
cp "$SOLE_TEST_DOWNLOADS/$file" "$output"
EOF
chmod +x "$temporary/tools/curl"
export SOLE_TEST_DOWNLOADS="$temporary/downloads" SOLE_VERSION=0.0.0
PATH="$temporary/tools:$PATH" sh "$root/install-release.sh" "$temporary/installed" > "$temporary/log"
test "$("$temporary/installed/bin/sole" --version)" = 'sole 0.0.0 (self-hosted)'
test -f "$temporary/installed/share/sole/lib/core.sole"
test -f "$temporary/installed/share/sole/runtime/system.c"

printf 'tampered' >> "$temporary/downloads/$archive.tar.gz"
if PATH="$temporary/tools:$PATH" sh "$root/install-release.sh" "$temporary/rejected" > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted a bad checksum' >&2
    exit 1
fi
test ! -e "$temporary/rejected"
if sh "$root/install-release.sh" relative-prefix > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted a relative prefix' >&2
    exit 1
fi
echo 'Passed release installer checks.'
