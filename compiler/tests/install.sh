#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-install-test-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

version=0.0.1
archive="sole-$version-linux-x86_64"
mkdir -p "$temporary/$archive/bin" "$temporary/$archive/share/sole"
install -m 755 "$root/.build/sole" "$temporary/$archive/bin/sole"
cp -R "$root/lib" "$temporary/$archive/share/sole/"
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
export SOLE_TEST_DOWNLOADS="$temporary/downloads" SOLE_VERSION="$version"
PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/installed" > "$temporary/log"
test "$("$temporary/installed/bin/sole" --version)" = "sole $version (self-hosted)"
test -f "$temporary/installed/share/sole/lib/core.sole"
test -f "$temporary/installed/share/sole/lib/runtime/system.c"

DESTDIR="$temporary/staged" PATH="$temporary/tools:$PATH" sh "$root/install.sh" /usr/local > "$temporary/log"
test -x "$temporary/staged/usr/local/bin/sole"
test -f "$temporary/staged/usr/local/share/sole/lib/runtime/core.ll"

printf 'tampered' >> "$temporary/downloads/$archive.tar.gz"
if PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/rejected" > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted a bad checksum' >&2
    exit 1
fi
test ! -e "$temporary/rejected"
if sh "$root/install.sh" relative-prefix > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted a relative prefix' >&2
    exit 1
fi
if sh "$root/install.sh" --source > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted --source' >&2
    exit 1
fi
echo 'Passed release installer checks.'
