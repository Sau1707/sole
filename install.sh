#!/bin/sh
set -eu

prefix=${1:-"$HOME/.local"}
version=${SOLE_VERSION:-latest}
if [ "$#" -gt 1 ]; then
    echo "Usage: sh install.sh [/absolute/prefix]" >&2
    exit 1
fi
case "$prefix" in
    /*) ;;
    *) echo "Installation prefix must be an absolute path." >&2; exit 1 ;;
esac
destination=${DESTDIR:-}$prefix
case "$version" in
    latest) ;;
    ''|*[!0-9.]*) echo "SOLE_VERSION must be a numeric version, such as 0.0.8." >&2; exit 1 ;;
esac
if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    echo "Prebuilt Sole releases support Linux x86-64 only." >&2
    exit 1
fi
case "${SOLE_INSTALL_DEPS:-1}" in
    0|1) ;;
    *) echo "SOLE_INSTALL_DEPS must be 0 or 1." >&2; exit 1 ;;
esac

install_dependencies() {
    if [ "${SOLE_INSTALL_DEPS:-1}" = 0 ] || [ -n "${DESTDIR:-}" ]; then
        echo "Install curl, coreutils, tar, gzip, awk, and a native C toolchain before installing Sole." >&2
        exit 1
    fi
    elevate=
    if [ "$(id -u)" != 0 ]; then
        command -v sudo >/dev/null || { echo "Installing dependencies requires root or sudo." >&2; exit 1; }
        elevate=sudo
    fi
    echo "Installing Sole's system dependencies (may request sudo access)."
    if command -v apt-get >/dev/null; then
        $elevate apt-get update
        $elevate apt-get install -y build-essential curl coreutils tar gzip gawk
    elif command -v dnf >/dev/null; then
        $elevate dnf install -y gcc glibc-devel binutils curl coreutils tar gzip gawk
    elif command -v yum >/dev/null; then
        $elevate yum install -y gcc glibc-devel binutils curl coreutils tar gzip gawk
    elif command -v pacman >/dev/null; then
        $elevate pacman -S --needed --noconfirm base-devel curl coreutils tar gzip gawk
    elif command -v zypper >/dev/null; then
        $elevate zypper --non-interactive install gcc glibc-devel binutils curl coreutils tar gzip gawk
    else
        echo "Unsupported package manager. Install the dependencies manually, then rerun install.sh." >&2
        exit 1
    fi
}

missing=0
for tool in curl sha256sum tar install awk gzip mktemp cp mkdir; do
    command -v "$tool" >/dev/null || missing=1
done
if [ "$missing" = 1 ]; then install_dependencies; fi
for tool in curl sha256sum tar install awk gzip mktemp cp mkdir; do
    command -v "$tool" >/dev/null || { echo "Install $tool first." >&2; exit 1; }
done

if [ "$version" = latest ]; then
    release_url=$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL -o /dev/null -w '%{url_effective}' \
        https://github.com/Sau1707/sole/releases/latest)
    case "$release_url" in
        https://github.com/Sau1707/sole/releases/tag/v*) version=${release_url##*/v} ;;
        *) echo "Could not determine the latest Sole release." >&2; exit 1 ;;
    esac
    case "$version" in
        ''|*[!0-9.]*) echo "The latest Sole release has an unsupported version: $version" >&2; exit 1 ;;
    esac
fi

temp_root=${TMPDIR:-/tmp}
if [ -z "${TMPDIR:-}" ] && [ -d /tmp/opencode ]; then temp_root=/tmp/opencode; fi
temporary=$(mktemp -d "$temp_root/sole-install-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

check_toolchain() {
    printf 'int main(void) { return 0; }\n' | "${SOLE_CC:-cc}" -x c - -o "$temporary/cc-test" > "$temporary/cc.log" 2>&1 &&
        "$temporary/cc-test" >> "$temporary/cc.log" 2>&1
}
archive="sole-$version-linux-x86_64"
base="https://github.com/Sau1707/sole/releases/download/v$version"
curl --proto '=https' --tlsv1.2 -fL "$base/$archive.tar.gz" -o "$temporary/$archive.tar.gz"
curl --proto '=https' --tlsv1.2 -fL "$base/SHA256SUMS" -o "$temporary/SHA256SUMS"
awk -v file="$archive.tar.gz" '$2 == file { print; found = 1 } END { if (!found) exit 1 }' \
    "$temporary/SHA256SUMS" > "$temporary/expected"
(cd "$temporary" && sha256sum -c expected)
tar -xzf "$temporary/$archive.tar.gz" -C "$temporary"
package="$temporary/$archive"
if [ ! -d "$package/lib/sole" ]; then
    echo "This release archive does not contain bundled libraries. A newly packaged release is required." >&2
    exit 1
fi
if [ "$("$package/bin/sole" --version)" != "sole $version (self-hosted)" ]; then
    echo "The downloaded compiler could not run or has the wrong version. This release requires a compatible Linux x86-64 glibc system." >&2
    exit 1
fi
if [ -z "${DESTDIR:-}" ] && ! check_toolchain; then
    if [ -n "${SOLE_CC:-}" ]; then
        echo "SOLE_CC=$SOLE_CC cannot compile and link a native C program." >&2
        cat "$temporary/cc.log" >&2
        exit 1
    fi
    install_dependencies
    if ! check_toolchain; then
        echo "The native C toolchain is still unusable after installing dependencies." >&2
        cat "$temporary/cc.log" >&2
        exit 1
    fi
fi
mkdir -p "$destination/bin" "$destination/lib/sole" "$destination/share/sole"
cp -R "$package/lib/sole/." "$destination/lib/sole/"
cp -R "$package/share/sole/." "$destination/share/sole/"
install -m 755 "$package/bin/sole" "$destination/bin/sole"
echo "Installed Sole $version in $destination"
echo "Add $prefix/bin to PATH to use sole."
