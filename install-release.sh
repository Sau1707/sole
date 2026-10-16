#!/bin/sh
set -eu

prefix=${1:-"$HOME/.local"}
version=${SOLE_VERSION:-0.0.0}
if [ "$#" -gt 1 ]; then
    echo "Usage: sh install-release.sh [/absolute/prefix]" >&2
    exit 1
fi
case "$prefix" in
    /*) ;;
    *) echo "Installation prefix must be an absolute path." >&2; exit 1 ;;
esac
case "$version" in
    ''|*[!0-9.]*) echo "SOLE_VERSION must be a numeric version, such as 0.0.0." >&2; exit 1 ;;
esac
if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    echo "Prebuilt Sole releases support Linux x86-64 only." >&2
    exit 1
fi
for tool in curl sha256sum tar install; do
    command -v "$tool" >/dev/null || { echo "Install $tool first." >&2; exit 1; }
done

temp_root=${TMPDIR:-/tmp}
if [ -z "${TMPDIR:-}" ] && [ -d /tmp/opencode ]; then temp_root=/tmp/opencode; fi
temporary=$(mktemp -d "$temp_root/sole-install-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
archive="sole-$version-linux-x86_64"
base="https://github.com/Sau1707/sole/releases/download/v$version"
curl --proto '=https' --tlsv1.2 -fL "$base/$archive.tar.gz" -o "$temporary/$archive.tar.gz"
curl --proto '=https' --tlsv1.2 -fL "$base/SHA256SUMS" -o "$temporary/SHA256SUMS"
awk -v file="$archive.tar.gz" '$2 == file { print; found = 1 } END { if (!found) exit 1 }' \
    "$temporary/SHA256SUMS" > "$temporary/expected"
(cd "$temporary" && sha256sum -c expected)
tar -xzf "$temporary/$archive.tar.gz" -C "$temporary"
package="$temporary/$archive"
if [ "$("$package/bin/sole" --version)" != "sole $version (self-hosted)" ]; then
    echo "The downloaded compiler could not run or has the wrong version. Install LLVM 21 (libLLVM.so.21.1) and its dependencies." >&2
    exit 1
fi
destination=${DESTDIR:-}$prefix
mkdir -p "$destination/bin" "$destination/share/sole"
cp -R "$package/share/sole/." "$destination/share/sole/"
install -m 755 "$package/bin/sole" "$destination/bin/sole"
echo "Installed Sole $version in $destination"
echo "Add $prefix/bin to PATH to use sole. Compilation requires a native C toolchain."
