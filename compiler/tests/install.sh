#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-install-test-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

version=0.0.13
archive="sole-$version-linux-x86_64"
mkdir "$temporary/downloads" "$temporary/tools"
if [ -n "${SOLE_TEST_RELEASE:-}" ]; then
    cp "$SOLE_TEST_RELEASE" "$temporary/downloads/$archive.tar.gz"
else
    mkdir -p "$temporary/$archive/bin" "$temporary/$archive/lib/sole" "$temporary/$archive/share/sole"
    compiler=$(command -v "${SOLE_COMPILER:-sole}")
    install -m 755 "$compiler" "$temporary/$archive/bin/sole"
    compiler_prefix=$(dirname -- "$(dirname -- "$compiler")")
    if [ -d "$compiler_prefix/lib/sole" ]; then
        cp -R "$compiler_prefix/lib/sole/." "$temporary/$archive/lib/sole/"
    fi
    cp -R "$root/lib" "$temporary/$archive/share/sole/"
    mkdir -p "$temporary/$archive/share/sole/compiler"
    cp -R "$root/compiler/raw" "$root/compiler/runtime" "$temporary/$archive/share/sole/compiler/"
    printf 'bundled-library-fixture\n' > "$temporary/$archive/lib/sole/test-library"
    tar -C "$temporary" -czf "$temporary/downloads/$archive.tar.gz" "$archive"
fi
(cd "$temporary/downloads" && sha256sum "$archive.tar.gz" > SHA256SUMS)
cat > "$temporary/tools/curl" <<'EOF'
#!/bin/sh
set -eu
file=
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        https://*/releases/latest)
            printf '%s\n' "${SOLE_TEST_LATEST_URL:-https://github.com/Sau1707/sole/releases/tag/v$SOLE_TEST_VERSION}"
            exit 0 ;;
        https://*/releases/download/v*)
            test "${1%/*}" = "https://github.com/Sau1707/sole/releases/download/v$SOLE_TEST_VERSION"
            file=${1##*/} ;;
        -o) shift; output=$1 ;;
    esac
    shift
done
cp "$SOLE_TEST_DOWNLOADS/$file" "$output"
EOF
chmod +x "$temporary/tools/curl"
export SOLE_TEST_DOWNLOADS="$temporary/downloads" SOLE_VERSION="$version" SOLE_TEST_VERSION="$version"
PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/installed" > "$temporary/log"
test "$("$temporary/installed/bin/sole" --version)" = "sole $version (self-hosted)"
test -f "$temporary/installed/share/sole/lib/core.sole"
test ! -e "$temporary/installed/share/sole/lib/runtime"
for resource in core.ll native.ll io.sole linux.sole system.sole; do
    test -f "$temporary/installed/share/sole/compiler/runtime/$resource"
done
test ! -e "$temporary/installed/share/sole/compiler/syntax"
test -f "$temporary/installed/share/sole/compiler/raw/c.sole"
test -f "$temporary/installed/share/sole/compiler/raw/llvm.sole"
test -f "$temporary/installed/share/sole/lib/pure/strings.sole"
test -f "$temporary/installed/share/sole/lib/pure/string_array.sole"
test ! -e "$temporary/installed/share/sole/lib/pure/bisect.sole"
test ! -e "$temporary/installed/share/sole/lib/pure/statistics.sole"
for primitive in str int uint float array; do
    test ! -e "$temporary/installed/share/sole/compiler/primitives/$primitive.sole"
done
if [ -n "${SOLE_TEST_RELEASE:-}" ]; then
    test -f "$temporary/installed/lib/sole/libLLVM.so.21.1"
    test -f "$temporary/installed/share/sole/licenses/common-licenses/Apache-2.0"
else
    cmp "$temporary/$archive/lib/sole/test-library" "$temporary/installed/lib/sole/test-library"
fi
mv "$temporary/installed" "$temporary/relocated"
test "$("$temporary/relocated/bin/sole" --version)" = "sole $version (self-hosted)"
"$temporary/relocated/bin/sole" check "$root/compiler/tests/cases/001-compile_without_python_on_path/source/hello.sole"
"$temporary/relocated/bin/sole" build "$root/compiler/tests/cases/001-compile_without_python_on_path/source/hello.sole" -o "$temporary/hello"
"$temporary/hello" > "$temporary/hello.log"

cat > "$temporary/main.sole" <<'EOF'
import raw.llvm as llvm
import env
import strings
import string_array


def main() -> int32:
    if ¢.sqrt(16.0) != 4.0 || ¢.abs(-9) != 9:
        return 1
    if env.get("SOLE_INSTALLED_BINDINGS_TEST", "") != "1":
        return 2
    if not strings.ends_with(strings.replace("ha-ha", "-", ""), "haha"):
        return 3
    if ¢.abs(-12) != 12:
        return 4
    names: str[] = ["a", "b"]
    if not string_array.contains(names, "b") || string_array.index_of(names, "a") != 0:
        return 5
    return 0
EOF
(
    unset SOLE_HOME SOLE_LIB
    "$temporary/relocated/bin/sole" build "$temporary/main.sole" -o "$temporary/bindings"
    SOLE_INSTALLED_BINDINGS_TEST=1 "$temporary/bindings"
)

DESTDIR="$temporary/staged" PATH="$temporary/tools:$PATH" sh "$root/install.sh" /usr/local > "$temporary/log"
test -x "$temporary/staged/usr/local/bin/sole"
test -f "$temporary/staged/usr/local/share/sole/compiler/runtime/core.ll"

(
    unset SOLE_VERSION
    DESTDIR="$temporary/latest" PATH="$temporary/tools:$PATH" sh "$root/install.sh" /usr/local > "$temporary/log"
)
test -x "$temporary/latest/usr/local/bin/sole"
if SOLE_VERSION=latest SOLE_TEST_LATEST_URL=https://github.com/Sau1707/sole/releases \
    PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/no-release" > "$temporary/log" 2>&1; then
    echo 'FAIL: installer accepted a missing latest release' >&2
    exit 1
fi
test ! -e "$temporary/no-release"

cat > "$temporary/tools/cc" <<'EOF'
#!/bin/sh
if [ ! -e "$SOLE_TEST_DEPENDENCIES" ]; then exit 1; fi
exec "$SOLE_TEST_CC" "$@"
EOF
cat > "$temporary/tools/apt-get" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SOLE_TEST_PACKAGES"
case "$1" in install) touch "$SOLE_TEST_DEPENDENCIES" ;; esac
EOF
cat > "$temporary/tools/id" <<'EOF'
#!/bin/sh
echo "${SOLE_TEST_UID:-0}"
EOF
cat > "$temporary/tools/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SOLE_TEST_SUDO"
exec "$@"
EOF
chmod +x "$temporary/tools/cc" "$temporary/tools/apt-get" "$temporary/tools/id" "$temporary/tools/sudo"
export SOLE_TEST_CC="$(command -v "${SOLE_CC:-cc}")"
export SOLE_TEST_DEPENDENCIES="$temporary/dependencies" SOLE_TEST_PACKAGES="$temporary/packages"
if SOLE_CC= PATH="$temporary/tools:$PATH" SOLE_INSTALL_DEPS=0 sh "$root/install.sh" "$temporary/no-deps" > "$temporary/log" 2>&1; then
    echo 'FAIL: installer ignored dependency opt-out' >&2
    exit 1
fi
test ! -e "$temporary/packages"
if SOLE_CC="$temporary/tools/cc" PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/bad-cc" > "$temporary/log" 2>&1; then
    echo 'FAIL: installer accepted unusable SOLE_CC' >&2
    exit 1
fi
test ! -e "$temporary/packages"
SOLE_CC= PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/with-deps" > "$temporary/log"
grep -qx update "$temporary/packages"
grep -qx 'install -y build-essential curl coreutils tar gzip gawk' "$temporary/packages"
test -x "$temporary/with-deps/bin/sole"
rm "$temporary/packages"
SOLE_CC= PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/existing-deps" > "$temporary/log"
test ! -e "$temporary/packages"
rm "$temporary/dependencies"
export SOLE_TEST_SUDO="$temporary/sudo"
SOLE_TEST_UID=1000 SOLE_CC= PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/with-sudo" > "$temporary/log"
grep -qx 'apt-get update' "$temporary/sudo"
grep -qx 'apt-get install -y build-essential curl coreutils tar gzip gawk' "$temporary/sudo"
rm "$temporary/packages" "$temporary/dependencies"
DESTDIR="$temporary/no-system-changes" SOLE_CC= PATH="$temporary/tools:$PATH" sh "$root/install.sh" /usr/local > "$temporary/log"
test ! -e "$temporary/packages"

printf 'tampered' >> "$temporary/downloads/$archive.tar.gz"
if PATH="$temporary/tools:$PATH" sh "$root/install.sh" "$temporary/rejected" > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted a bad checksum' >&2
    exit 1
fi
test ! -e "$temporary/rejected"
test ! -e "$temporary/packages"
if sh "$root/install.sh" relative-prefix > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted a relative prefix' >&2
    exit 1
fi
if sh "$root/install.sh" --source > "$temporary/log" 2>&1; then
    echo 'FAIL: release installer accepted --source' >&2
    exit 1
fi
echo 'Passed release installer checks.'
