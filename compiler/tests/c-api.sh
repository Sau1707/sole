#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-c-api-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/helper.sole" <<'EOF'
def size(text: ptr) -> uint64:
    return ¢.strlen(text)
EOF
cat > "$temporary/main.sole" <<'EOF'
import core
import helper
import raw.c as legacy


def abs(value: int32) -> int32:
    return 99


def main() -> int32:
    data: ptr = ¢.malloc(8)
    if data == ptr(0):
        return 1
    ¢.memcpy(data, core.cstr("¢.literal"), 8)
    result: int32 = 0
    if ¢.memcmp(data, core.cstr("¢.literal"), 8) != 0:
        result = 2
    if helper.size(core.cstr("¢")) != 2:
        result = 3
    if ¢.abs(-7) != 7 || abs(-7) != 99 || legacy.abs(-7) != 7:
        result = 4
    if ¢.sqrt(16.0) != 4.0 || ¢.pow(2.0, 3.0) != 8.0:
        result = 5
    ¢.free(data)
    return result
EOF
"$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole"
"$compiler" check "$temporary/main.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    "$temporary/program"
done

mkdir "$temporary/raw"
printf 'def abs(value: str) -> str:\n    return value\n' > "$temporary/raw/c.sole"
cat > "$temporary/main.sole" <<'EOF'
def main() -> int32:
    if ¢.abs(-7) == 7:
        return 0
    return 1
EOF
"$compiler" build "$temporary/main.sole" -o "$temporary/program"
"$temporary/program"

reject() {
    printf '%s\n' "$1" > "$temporary/main.sole"
    for command in check build; do
        status=0
        "$compiler" "$command" "$temporary/main.sole" > "$temporary/error" 2>&1 || status=$?
        test "$status" -eq 1
        grep -Fq "$2" "$temporary/error"
        grep -Fq "$temporary/main.sole:" "$temporary/error"
    done
}

reject 'def main() -> void:
    ¢.not_a_c_function()' "C API has no declaration 'not_a_c_function'"
reject 'def main() -> void:
    ¢.LLVMContextCreate()' "C API has no declaration 'LLVMContextCreate'"
reject 'def main() -> void:
    ¢.malloc("8")' 'expected uint64, got str'
reject 'def main() -> void:
    ¢.free()' 'wrong number of arguments'
reject 'def main() -> void:
    ¢.malloc(size=8)' 'named arguments are only supported for record constructors'
reject 'def main() -> void:
    ¢' "expected a C API name after '¢.'"
reject 'def main() -> void:
    ¢.' "expected a C API name after '¢.'"
reject 'def main() -> void:
    ¢.abs = 1' 'C API names cannot be declared or rebound'
reject 'def ¢.abs(value: int32) -> int32:
    return value' 'C API names cannot be declared or rebound'
reject 'def main() -> void:
    sqrt(4.0)' 'unknown function'

echo 'Passed built-in C namespace execution, isolation, and diagnostics checks.'
