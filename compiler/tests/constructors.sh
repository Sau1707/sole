#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-constructors-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cp "$root/compiler/tests/source-cases/constructors/records.sole" "$temporary/records.sole"

cp "$root/compiler/tests/source-cases/constructors/main.sole" "$temporary/main.sole"

"$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole"
"$compiler" check "$temporary/main.sole"
printf 'constructors passed\n' > "$temporary/expected"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    "$temporary/program" > "$temporary/actual"
    cmp "$temporary/expected" "$temporary/actual"
done

reject() {
    expression=$1
    diagnostic=$2
    cat > "$temporary/bad.sole" <<EOF
struct Pair:
    first: int32
    second: int32


def identity(value: int32) -> int32:
    return value


class Method:
    def identity(self, value: int32) -> int32:
        return value


def main() -> int32:
    $expression
    return 0
EOF
    for command in check build; do
        status=0
        "$compiler" "$command" "$temporary/bad.sole" > "$temporary/error" 2>&1 || status=$?
        if [ "$status" -ne 1 ]; then
            cat "$temporary/error" >&2
            echo "FAIL: $command returned $status for $expression" >&2
            exit 1
        fi
        grep -Fq "$diagnostic" "$temporary/error"
    done
}

reject 'pair: Pair = Pair(first=1, first=2, second=3)' "duplicate constructor field 'first'"
reject 'pair: Pair = Pair(1, first=2, second=3)' "duplicate constructor field 'first'"
reject 'pair: Pair = Pair(unknown=1, second=2)' "unknown constructor field 'unknown'"
reject 'pair: Pair = Pair(second=2)' "missing constructor field 'first'"
reject 'pair: Pair = Pair()' "missing constructor field 'first'"
reject 'pair: Pair = Pair(1)' "missing constructor field 'second'"
reject 'pair: Pair = Pair(1, 2, 3)' 'wrong number of constructor fields'
reject 'pair: Pair = Pair(first=1, 2)' 'positional argument cannot follow named constructor arguments'
reject 'value: int32 = identity(value=1)' 'named arguments are only supported for record constructors'
reject 'value: int32 = Method().identity(value=1)' 'named arguments are only supported for record constructors'
reject 'pair: Pair = Pair(second=2, first="wrong")' 'expected int32, got str'

echo 'Passed named constructor execution and validation checks.'
