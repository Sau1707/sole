#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-constructors-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/records.sole" <<'EOF'
struct Pair:
    first: int32
    second: int32


class Box:
    small: uint8
    items: int16[]


struct Labels:
    identity: int32
    models: int32
EOF

cat > "$temporary/main.sole" <<'EOF'
import core
import records as models


struct Pair:
    first: int32
    second: int32


class Trace:
    digits: int32


class Box:
    pair: Pair
    data: int16[2]
    def sum(self) -> int32:
        return self.pair.first + self.pair.second


struct Numbers:
    small: int8
    byte: uint8
    real: float32
    fixed: int16[2]
    dynamic: uint8[]


struct Empty:
    pass


def mark(trace: Trace, digit: int32) -> int32:
    trace.digits = trace.digits * 10 + digit
    return digit


def identity(value: int32) -> int32:
    return value


def main() -> int32:
    trace: Trace = Trace(digits=0)
    pair: Pair = Pair(second=mark(trace, 2), first=mark(trace, 1))
    if trace.digits != 21 || pair.first != 1 || pair.second != 2:
        return 1
    mixed: Pair = Pair(mark(trace, 3), second=mark(trace, 4))
    if trace.digits != 2134 || mixed.first != 3 || mixed.second != 4:
        return 2
    box: Box = Box(data=[7, 8], pair=Pair(second=6, first=5))
    if box.sum() != 11 || box.data[0] != 7 || box.data[1] != 8:
        return 3
    numbers: Numbers = Numbers(dynamic=[0, 255], fixed=[-32768, 32767], real=1.5, byte=255, small=-128)
    if numbers.small != -128 || numbers.byte != 255 || numbers.real != 1.5:
        return 4
    if numbers.fixed[0] != -32768 || numbers.fixed[1] != 32767 || numbers.dynamic[1] != 255:
        return 5
    imported: models.Pair = models.Pair(second=10, first=9)
    reference: models.Box = models.Box(items=[11, 12], small=255)
    if imported.first != 9 || imported.second != 10 || reference.small != 255 || reference.items[1] != 12:
        return 6
    positional: Pair = Pair(13, 14)
    empty: Empty = Empty()
    if identity(positional.first) != 13 || positional.second != 14:
        return 7
    class_trace: Trace = Trace(0)
    class_box: Box = Box(data=[int16(mark(class_trace, 1)), int16(mark(class_trace, 2))], pair=Pair(mark(class_trace, 3), mark(class_trace, 4)))
    if class_trace.digits != 1234 || class_box.sum() != 7:
        return 8
    labels: models.Labels = models.Labels(models=2, identity=1)
    if labels.identity != 1 || labels.models != 2:
        return 9
    core.print("constructors passed")
    return 0
EOF

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
