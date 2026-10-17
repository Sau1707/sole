#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p .build
cc=${SOLE_CC:-cc}
llvm_library=${SOLE_LLVM_LIB:-LLVM-21}
seed=${SOLE_BOOTSTRAP:-sole}
if ! command -v "$seed" >/dev/null; then
    echo "Install Sole first or set SOLE_BOOTSTRAP to an existing compiler." >&2
    exit 1
fi
command -v "$cc" >/dev/null
export SOLE_HOME="$PWD" SOLE_LIB="$PWD/lib"
seed_home=$(mktemp -d "$PWD/.build/seed-home-XXXXXX")
trap 'rm -rf -- "$seed_home"' EXIT HUP INT TERM
cp -R "$PWD/lib" "$seed_home/lib"
cp -R "$PWD/compiler" "$seed_home/compiler"

# Older seeds use explicit imports for the built-in C namespace.
find "$seed_home/compiler" "$seed_home/lib" -path "$seed_home/compiler/tests" -prune -o -type f -name '*.sole' -print |
while IFS= read -r source; do
    if grep -q '¢[.]' "$source"; then
        {
            printf 'import raw.c as bootstrap_c_api\n'
            sed 's/¢[.]/bootstrap_c_api./g' "$source"
        } > "$seed_home/translated.sole"
        mv "$seed_home/translated.sole" "$source"
    fi
done
seed_prefix=$(dirname -- "$(dirname -- "$(command -v "$seed")")")
seed_resources=${SOLE_BOOTSTRAP_HOME:-$seed_prefix/share/sole}
if [ -f "$seed_resources/lib/runtime/system.c" ]; then
    cp "$seed_resources/lib/runtime/system.c" "$seed_home/lib/runtime/system.c"
    cp "$seed_resources/lib/runtime/native.ll" "$seed_home/lib/runtime/native.ll"
fi
ln -s "$seed_home/lib/runtime" "$seed_home/runtime"
ln -s "$seed_home/compiler/raw" "$seed_home/lib/raw"
SOLE_HOME="$seed_home" SOLE_LIB="$seed_home/lib" "$seed" build "$seed_home/compiler/main.sole" --link "$llvm_library" -o .build/sole-stage1
.build/sole-stage1 build compiler/main.sole --link "$llvm_library" -o .build/sole-stage2
.build/sole-stage2 build compiler/main.sole --link "$llvm_library" -o .build/sole-stage3
cmp .build/sole-stage2 .build/sole-stage3
install -m 755 .build/sole-stage3 .build/sole
sha256sum .build/sole-stage2 .build/sole-stage3 > .build/bootstrap-proof.txt
find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -print | LC_ALL=C sort | while IFS= read -r source; do
    sha256sum "$source"
done >> .build/bootstrap-proof.txt
sha256sum lib/runtime/*.ll >> .build/bootstrap-proof.txt
rm -- .build/sole-stage1
echo "Verified: stage 2 and stage 3 are byte-for-byte identical."
