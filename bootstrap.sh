#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
mkdir -p .build

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--seed" ]; }; then
    echo "Usage: ./bootstrap.sh [--seed]" >&2
    exit 1
fi

cc=${SOLE_CC:-cc}
llvm_library=${SOLE_LLVM_LIB:-}
if [ -z "$llvm_library" ]; then
    for candidate in LLVM-22 LLVM-21 LLVM-20 LLVM-19 LLVM-18 LLVM; do
        found=$("$cc" -print-file-name="lib$candidate.so")
        if [ "$found" != "lib$candidate.so" ]; then
            llvm_library=$candidate
            break
        fi
    done
fi
if [ -z "$llvm_library" ]; then
    echo "Install a shared LLVM library (e.g. libllvm21), or set SOLE_LLVM_LIB to its linker name." >&2
    exit 1
fi

if [ -n "${SOLE_BOOTSTRAP:-}" ]; then
    seed=$SOLE_BOOTSTRAP
elif [ -x .build/sole ] && [ "${1:-}" != "--seed" ]; then
    seed=.build/sole
else
    if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
        echo "The bundled seed requires Linux x86-64. Set SOLE_BOOTSTRAP to a compatible Sole compiler." >&2
        exit 1
    fi
    sha256sum -c bootstrap/SHA256SUMS
    seed=bootstrap/sole
fi

export SOLE_HOME="$PWD" SOLE_LIB="$PWD/lib"
echo "Bootstrapping with $seed (native Sole)."
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
echo "Verified: stage 2 and stage 3 are byte-for-byte identical. Compiler: .build/sole"
