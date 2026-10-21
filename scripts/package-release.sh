#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
version=${1:?Usage: sh scripts/package-release.sh VERSION}
case "$version" in
    ''|*[!0-9.]*) echo "Invalid release version." >&2; exit 1 ;;
esac
for tool in patchelf ldd dpkg-query; do
    command -v "$tool" >/dev/null || { echo "Packaging requires $tool (on Debian/Ubuntu)." >&2; exit 1; }
done
test "$(.build/sole --version)" = "sole $version (self-hosted)"
archive="sole-$version-linux-x86_64"
package=".build/$archive"
test ! -e "$package" || { echo "$package already exists; use a clean packaging directory." >&2; exit 1; }
mkdir -p "$package/bin" "$package/lib/sole" "$package/share/sole/licenses"
install -m 755 .build/sole "$package/bin/sole"
cp -R lib "$package/share/sole/"
mkdir -p "$package/share/sole/compiler"
cp -R compiler/raw compiler/runtime "$package/share/sole/compiler/"
cp -R /usr/share/common-licenses "$package/share/sole/licenses/"
cp README.md .build/bootstrap-proof.txt "$package/"
ldd .build/sole > "$package/dependencies.txt"
if grep -q 'not found' "$package/dependencies.txt"; then
    cat "$package/dependencies.txt" >&2
    exit 1
fi
awk '$2 == "=>" && $3 ~ /^\// { print $1, $3 }' "$package/dependencies.txt" |
while read -r name source; do
    case "$name" in
        libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|ld-linux*) continue ;;
    esac
    install -m 755 "$source" "$package/lib/sole/$name"
    patchelf --set-rpath '$ORIGIN' "$package/lib/sole/$name"
    resolved=$(readlink -f "$source")
    owner=$( { dpkg-query -S "$resolved" 2>/dev/null || dpkg-query -S "$source"; } |
        head -n 1 | sed 's/: \/.*//; s/:.*//')
    test -n "$owner"
    install -m 644 "/usr/share/doc/$owner/copyright" "$package/share/sole/licenses/$owner.copyright"
done
test -f "$package/lib/sole/libLLVM.so.21.1"
patchelf --set-rpath '$ORIGIN/../lib/sole' "$package/bin/sole"
test "$("$package/bin/sole" --version)" = "sole $version (self-hosted)"
mkdir -p dist
install -m 755 install.sh dist/install.sh
tar -C .build -czf "dist/$archive.tar.gz" "$archive"
(cd dist && sha256sum "$archive.tar.gz" > SHA256SUMS)
