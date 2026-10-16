#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
prefix=${1:-"$HOME/.local"}
case "$prefix" in
    /*) ;;
    *) echo "Installation prefix must be an absolute path." >&2; exit 1 ;;
esac
if [ ! -x .build/sole ]; then
    echo "Run ./bootstrap.sh before installing." >&2
    exit 1
fi
destination=${DESTDIR:-}$prefix
mkdir -p "$destination/bin" "$destination/share/sole"
install -m 755 .build/sole "$destination/bin/sole"
cp -R runtime lib "$destination/share/sole/"
echo "Installed Sole in $destination"
