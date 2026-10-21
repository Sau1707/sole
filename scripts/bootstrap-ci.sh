#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p .build
llvm_library=${SOLE_LLVM_LIB:-LLVM-21}
seed=${SOLE_BOOTSTRAP:-sole}
if ! command -v "$seed" >/dev/null; then
    echo "Install Sole first or set SOLE_BOOTSTRAP to an existing compiler." >&2
    exit 1
fi
command -v "${SOLE_CC:-cc}" >/dev/null
export SOLE_HOME="$PWD" SOLE_LIB="$PWD/lib"
"$seed" build compiler/main.sole --link "$llvm_library" -o .build/sole-stage1
.build/sole-stage1 build compiler/main.sole --link "$llvm_library" -o .build/sole-stage2
.build/sole-stage2 build compiler/main.sole --link "$llvm_library" -o .build/sole-stage3
cmp .build/sole-stage2 .build/sole-stage3
install -m 755 .build/sole-stage3 .build/sole
sha256sum .build/sole-stage2 .build/sole-stage3 > .build/bootstrap-proof.txt
find compiler lib -path compiler/tests -prune -o -type f -name '*.sole' -print | LC_ALL=C sort | while IFS= read -r source; do
    sha256sum "$source"
done >> .build/bootstrap-proof.txt
sha256sum compiler/runtime/*.ll >> .build/bootstrap-proof.txt
rm -- .build/sole-stage1
echo "Verified: stage 2 and stage 3 are byte-for-byte identical."
