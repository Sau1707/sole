#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-features-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/main.sole" <<'EOF'
enum Direction:
    Left
    Right


struct Span:
    first: int64
    second: int64


union Node:
    Span(span: Span, direction: Direction)
    Empty()


class Counter:
    calls: int64


def choose(counter: Counter, n: int64) -> Node:
    counter.calls = counter.calls + 1
    if n == 0:
        return Node.Empty()
    return Node.Span(Span(second=n, first=1), Direction.Left)


def main() -> int32:
    counter: Counter = Counter(calls=0)
    total: int64 = 0
    for i in range(0, 5):
        match choose(counter, i):
            case Node.Span(span, direction):
                match direction:
                    case Direction.Left:
                        if span.second == 1:
                            continue
                        if span.second == 4:
                            break
                        total += span.first + span.second
                    case Direction.Right:
                        return 99
            case Node.Empty():
                total += 10
    if counter.calls != 5 || total != 17:
        return 1
    i: int64 = 3
    span: Span = Span(first=i, second=total)
    if span.first != 3 || span.second != 17:
        return 2
    return 0
EOF

"$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole"
"$compiler" check "$temporary/main.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    timeout 10 "$temporary/program"
done

cat > "$temporary/payloads.sole" <<'EOF'
import core


struct Data:
    value: int64


class Box:
    value: int64


union Payload:
    Value(data: Data)
    Shared(box: Box, items: int64[])


def main() -> int32:
    original: Payload = Payload.Value(Data(value=7))
    match original:
        case Payload.Value(data):
            data.value = 99
        case Payload.Shared(box, items):
            return 1
    match original:
        case Payload.Value(data):
            if data.value != 7:
                return 2
        case Payload.Shared(box, items):
            return 3
    shared: Box = Box(value=1)
    array: int64[] = []
    match Payload.Shared(shared, array):
        case Payload.Value(data):
            return 4
        case Payload.Shared(box, items):
            box.value = 10
            core.append(items, 20)
    if shared.value != 10 || core.len(array) != 1 || array[0] != 20:
        return 5
    return 0
EOF
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/payloads.sole" "$optimize" -o "$temporary/payloads"
    "$temporary/payloads"
done

for name in integer real; do
    for declaration in enum union; do
        member=A
        if [ "$declaration" = union ]; then member='A()'; fi
        printf '%s %s:\n    %s\n\n\ndef main() -> int32:\n    return 0\n' "$declaration" "$name" "$member" > "$temporary/reserved.sole"
        for command in check build; do
            status=0
            "$compiler" "$command" "$temporary/reserved.sole" > "$temporary/error" 2>&1 || status=$?
            test "$status" -eq 1
            grep -Fq 'duplicate or reserved type' "$temporary/error"
        done
    done
done

for declaration in enum union; do
    first='A'
    second='B'
    if [ "$declaration" = union ]; then
        first='A()'
        second='B()'
    fi
    cat > "$temporary/invalid-tag.sole" <<EOF
import core


extern def memcpy(destination: ptr, source: ptr, count: uint64) -> ptr


$declaration Kind:
    $first
    $second


def main() -> int32:
    value: Kind = Kind.$first
    invalid: int32 = 123
    memcpy(core.address(value), core.address(invalid), 4)
    match value:
        case Kind.$first:
            return 0
        case Kind.$second:
            return 1
EOF
    for optimize in -O0 -O2; do
        "$compiler" build "$temporary/invalid-tag.sole" "$optimize" -o "$temporary/invalid-tag"
        status=0
        "$temporary/invalid-tag" > "$temporary/output" 2>&1 || status=$?
        test "$status" -gt 128
        signal=$(kill -l "$status")
        case "$signal" in
            ILL|SIGILL|TRAP|SIGTRAP) ;;
            *) echo "FAIL: invalid $declaration tag produced $signal" >&2; exit 1 ;;
        esac
    done
done
echo 'Passed combined constructor, enum, union, match, range, and += checks.'
