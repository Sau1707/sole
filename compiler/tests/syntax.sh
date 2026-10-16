#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-syntax-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

syntax() {
    SOLE_HOME="$root" "$compiler" syntax --grammar "$root/compiler/sole.ebnf" "$@"
}

if [ "$#" -gt 0 ]; then
    syntax "$@"
    exit 0
fi

for arguments in '' '--grammar' '--grammar missing.ebnf'; do
    if "$compiler" syntax $arguments > "$temporary/error" 2>&1; then
        echo 'FAIL: syntax accepted missing arguments' >&2
        exit 1
    fi
    grep -q 'Usage: sole syntax' "$temporary/error"
done
printf 'def main() -> int32:\n    return missing_name\n' > "$temporary/syntax-only.sole"
SOLE_LIB=/no/such/library SOLE_CC=/no/such/linker syntax "$temporary/syntax-only.sole"
printf 'not source\n' > "$temporary/wrong.txt"
if syntax "$temporary/wrong.txt" > "$temporary/error" 2>&1; then
    echo 'FAIL: syntax accepted a non-Sole file' >&2
    exit 1
fi
grep -q 'expected a .sole file' "$temporary/error"

find "$root/compiler" "$root/lib" -path "$root/compiler/tests" -prune -o -type f -name '*.sole' \
    -exec env SOLE_HOME="$root" "$compiler" syntax --grammar "$root/compiler/sole.ebnf" {} +
if [ -d "$root/examples" ]; then
    find "$root/examples" -type f -name '*.sole' -exec env SOLE_HOME="$root" "$compiler" syntax --grammar "$root/compiler/sole.ebnf" {} +
fi
for fixture in "$root"/compiler/tests/cases/*; do
    case $(cat "$fixture/mode") in reject-*) continue ;; esac
    find "$fixture" -type f -name '*.sole' -exec env SOLE_HOME="$root" "$compiler" syntax --grammar "$root/compiler/sole.ebnf" {} +
done

reject() {
    printf '%s\n' "$1" > "$temporary/bad.sole"
    if syntax "$temporary/bad.sole" > "$temporary/error" 2>&1; then
        echo "FAIL: grammar accepted: $1" >&2
        exit 1
    fi
    grep -q 'error' "$temporary/error"
}

reject 'def main() -> int32
    return 0'
reject 'def main() -> int32:
return 0'
reject 'def main() -> int32:
    value: int32 ='
reject 'def main() -> int32:
    return 1 < 2 < 3'
reject 'def main() -> int32:
    value: int32 = 1
    value -= 2'
reject 'def main() -> int32:
    for value in values:
        pass'
reject 'struct Value:
    def get(self) -> int32:
        return 1'
reject 'def main() -> int32:
    return 0;'
reject 'import core as return'
reject 'def main() -> int32:
    return "return" +'
reject 'def main() -> int32:
    value: bool = true and false'
reject 'def main() -> int32:
    value: bool = true or false'

cat > "$temporary/features.sole" <<'EOF'
enum Kind:
    Number
    Text


union Item:
    Number(value: int64)
    Empty()


struct Pair:
    first: int64
    second: int64


def main() -> int32:
    pair: Pair = Pair(second=2, first=1)
    total: int64 = 0
    for i in range(0, pair.second):
        total += i
    item: Item = Item.Number(total)
    match item:
        case Item.Number(value):
            return int32(value)
        case Item.Empty():
            return 0
EOF
syntax "$temporary/features.sole"
reject 'enum Empty:'
reject 'union Item:
    Value(value int64)'
reject 'def main() -> int32:
    match value:
        case Item.Value(x) if true:
            return 0'
reject 'def main() -> int32:
    for i in range():
        pass'
reject 'def main() -> int32:
    for i in range(0, 3, 1):
        pass'

# Prove that the file, rather than a hard-coded Sole parser, drives acceptance.
printf 'program = "pass", NEWLINE, EOF;\n' > "$temporary/minimal.ebnf"
printf 'pass\n' > "$temporary/pass.sole"
"$compiler" syntax --grammar "$temporary/minimal.ebnf" "$temporary/pass.sole"
if syntax "$temporary/pass.sole" > "$temporary/error" 2>&1; then
    echo 'FAIL: Sole grammar accepted a module-level pass' >&2
    exit 1
fi
printf 'program = missing;\n' > "$temporary/invalid.ebnf"
if "$compiler" syntax --grammar "$temporary/invalid.ebnf" "$temporary/pass.sole" > "$temporary/error" 2>&1; then
    echo 'FAIL: undefined grammar rule accepted' >&2
    exit 1
fi
grep -q 'unknown grammar rule missing' "$temporary/error"
printf 'def main() -> int32:\n    return 0\n' > "$temporary/good.sole"
syntax "$temporary/good.sole" "$temporary/syntax-only.sole"
if syntax "$temporary/good.sole" "$temporary/pass.sole" > "$temporary/error" 2>&1; then
    echo 'FAIL: syntax ignored an invalid later input' >&2
    exit 1
fi
grep -Fq "$temporary/pass.sole:" "$temporary/error"
echo 'Passed EBNF syntax checks, rejection cases, and grammar-driven acceptance.'
