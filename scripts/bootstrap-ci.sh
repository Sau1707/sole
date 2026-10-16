#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p .build
cc=${SOLE_CC:-cc}
llvm_library=${SOLE_LLVM_LIB:-LLVM-21}
seed=${SOLE_BOOTSTRAP:-bootstrap/sole}
if [ "$seed" = bootstrap/sole ]; then
    if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
        echo "The bundled seed requires Linux x86-64." >&2
        exit 1
    fi
    sha256sum -c bootstrap/SHA256SUMS
fi
command -v "$cc" >/dev/null
export SOLE_HOME="$PWD" SOLE_LIB="$PWD/lib"
seed_home=$(mktemp -d "$PWD/.build/seed-home-XXXXXX")
trap 'rm -rf -- "$seed_home"' EXIT HUP INT TERM
ln -s "$PWD/lib" "$seed_home/lib"
ln -s "$PWD/lib/runtime" "$seed_home/runtime"
SOLE_HOME="$seed_home" "$seed" build compiler/main.sole --link "$llvm_library" -o .build/sole-stage1
.build/sole-stage1 build compiler/main.sole --link "$llvm_library" -o .build/sole-stage2
.build/sole-stage2 build compiler/main.sole --link "$llvm_library" -o .build/sole-stage3
cmp .build/sole-stage2 .build/sole-stage3
install -m 755 .build/sole-stage3 .build/sole
sha256sum .build/sole-stage2 .build/sole-stage3 > .build/bootstrap-proof.txt
find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -print | LC_ALL=C sort | while IFS= read -r source; do
    sha256sum "$source"
done >> .build/bootstrap-proof.txt
sha256sum lib/runtime/*.ll lib/runtime/system.c >> .build/bootstrap-proof.txt
rm -- .build/sole-stage1
echo "Verified: stage 2 and stage 3 are byte-for-byte identical."
