#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
cc=${SOLE_CC:-cc}
llvm_library=${SOLE_LLVM_LIB:-LLVM-21}
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-raw-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cp "$root/compiler/tests/raw.sole" "$temporary/main.sole"
ln -s "$root/compiler/codegen" "$temporary/codegen"
for optimize in 0 2; do
    "$compiler" build "$temporary/main.sole" "-O$optimize" --link "$llvm_library" -o "$temporary/raw-test"
    "$temporary/raw-test" "$temporary/raw.o" "$optimize"
    "$cc" "$root/compiler/tests/raw.c" "$temporary/raw.o" -lm -o "$temporary/native-test"
    "$temporary/native-test"
done

sed -n 's/^extern def \([A-Za-z0-9_]*\)(.*$/extern void \1(void);/p' \
    "$root/compiler/raw/llvm.sole" > "$temporary/symbols.c"
printf 'void (*volatile symbols[])(void) = {\n' >> "$temporary/symbols.c"
sed -n 's/^extern def \([A-Za-z0-9_]*\)(.*$/    \1,/p' \
    "$root/compiler/raw/llvm.sole" >> "$temporary/symbols.c"
cat >> "$temporary/symbols.c" <<'EOF'
};
int main(void) {
    for (unsigned i = 0; i < sizeof(symbols) / sizeof(symbols[0]); i++) {
        if (!symbols[i]) return 1;
    }
    return 0;
}
EOF
"$cc" "$temporary/symbols.c" "-l$llvm_library" -o "$temporary/symbols-test"
"$temporary/symbols-test"

cat > "$temporary/main.sole" <<'EOF'
import raw.llvm as llvm


def main() -> void:
    llvm.LLVMIntTypeInContext(ptr(0), "64")
EOF
status=0
"$compiler" check "$temporary/main.sole" > "$temporary/error" 2>&1 || status=$?
test "$status" -eq 1
grep -Fq 'expected uint32, got str' "$temporary/error"

cat > "$temporary/main.sole" <<'EOF'
import raw.llvm as llvm


def main() -> void:
    llvm.LLVMBuildAdd(ptr(0))
EOF
status=0
"$compiler" check "$temporary/main.sole" > "$temporary/error" 2>&1 || status=$?
test "$status" -eq 1
grep -Fq 'wrong number of arguments' "$temporary/error"

for index in '-1' 'core.arg_count()'; do
    printf 'import core\n\ndef main() -> void:\n    core.print(core.arg(%s))\n' "$index" > "$temporary/main.sole"
    for optimize in -O0 -O2; do
        "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/arguments-test"
        status=0
        "$temporary/arguments-test" > "$temporary/output" 2> "$temporary/error" || status=$?
        test "$status" -eq 1
        test ! -s "$temporary/output"
        grep -Fxq 'sole: argument index out of bounds' "$temporary/error"
    done
done
echo 'Passed raw LLVM/C bindings, symbol availability, and generated native execution checks.'
