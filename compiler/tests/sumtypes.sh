#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-sumtypes-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/models.sole" <<'EOF'
enum Kind:
    Number
    Text


union Item:
    Number(value: int64)
    Text(value: str)
    Empty()


def Number() -> int64:
    return 9


def value() -> int64:
    return 10


def score(item: Item) -> int64:
    match item:
        case Item.Number(n):
            return n
        case Item.Text(s):
            return 2
        case Item.Empty():
            return 0
EOF

cat > "$temporary/main.sole" <<'EOF'
import core
import models as first
import models as second


enum Kind:
    Number
    Text


union Item:
    Number(value: int64)
    Text(value: str)
    Empty()
    Data(values: int16[2], kinds: Kind[], other: first.Item)


struct Box:
    item: Item
    kind: Kind


class Trace:
    calls: int32


class Node:
    child: Link


union Link:
    Ref(node: Node)
    Many(items: Link[])
    End()


def once(trace: Trace) -> Item:
    trace.calls = trace.calls + 1
    return Item.Number(42)


def identity(item: Item) -> Item:
    return item


def score(item: Item) -> int64:
    match item:
        case Item.Number(value):
            value = value + 1
            return value
        case Item.Text(value):
            return core.len(value)
        case Item.Empty():
            return 0
        case Item.Data(values, kinds, other):
            match kinds[0]:
                case Kind.Number:
                    return int64(values[0]) + first.score(other)
                case Kind.Text:
                    return 99


def main() -> int32:
    trace: Trace = Trace(0)
    match once(trace):
        case Item.Text(value):
            return 1
        case Item.Empty():
            return 2
        case Item.Data(values, kinds, other):
            return 3
        case Item.Number(value):
            if value == 42:
                scoped: int64 = value + 1
                value = scoped
            if value != 43:
                return 4
            value = 5
    value: int64 = 8
    scoped: int64 = 9
    if trace.calls != 1 || value != 8 || scoped != 9:
        return 5
    if Kind.Number != Kind.Number || Kind.Number == Kind.Text:
        return 6
    box: Box = Box(identity(Item.Text("abc")), Kind.Text)
    items: Item[3] = [Item.Number(10), box.item, Item.Empty()]
    dynamic: Item[] = []
    core.append(dynamic, Item.Number(20))
    if score(items[0]) != 11 || score(items[1]) != 3 || score(items[2]) != 0 || score(dynamic[0]) != 21:
        return 7
    data: Item = Item.Data([7, 8], [Kind.Number], second.Item.Number(9))
    if score(data) != 16 || box.kind != Kind.Text:
        return 8
    imported: first.Kind = second.Kind.Number
    match imported:
        case second.Kind.Text:
            return 9
        case first.Kind.Number:
            pass
    count: int32 = 0
    while count < 3:
        count = count + 1
        match Item.Empty():
            case Item.Number(n):
                break
            case Item.Text(s):
                break
            case Item.Data(a, b, c):
                break
            case Item.Empty():
                continue
    if count != 3:
        return 11
    core.print("sumtypes passed")
    return 0
EOF

"$compiler" check "$temporary/main.sole"
printf 'sumtypes passed\n' > "$temporary/expected"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    "$temporary/program" > "$temporary/actual"
    cmp "$temporary/expected" "$temporary/actual"
done

reject() {
    diagnostic=$1
    cat > "$temporary/bad.sole"
    for optimize in -O0 -O2; do
        status=0
        "$compiler" build "$temporary/bad.sole" "$optimize" -o "$temporary/bad-program" > "$temporary/error" 2>&1 || status=$?
        if [ "$status" -ne 1 ]; then
            cat "$temporary/error" >&2
            echo "FAIL: expected rejection, got $status ($diagnostic)" >&2
            exit 1
        fi
        if ! grep -Fq "$diagnostic" "$temporary/error"; then
            cat "$temporary/error" >&2
            echo "FAIL: missing diagnostic: $diagnostic" >&2
            exit 1
        fi
    done
}

reject 'non-exhaustive match' <<'EOF'
enum Kind:
    A
    B
def main() -> int32:
    match Kind.A:
        case Kind.A:
            return 0
EOF

reject 'duplicate match case' <<'EOF'
enum Kind:
    A
def main() -> int32:
    match Kind.A:
        case Kind.A:
            pass
        case Kind.A:
            pass
    return 0
EOF

reject 'case belongs to a different type' <<'EOF'
enum One:
    A
enum Two:
    A
def main() -> int32:
    match One.A:
        case Two.A:
            return 0
EOF

reject 'wrong number of pattern bindings' <<'EOF'
union Item:
    Data(n: int64)
def main() -> int32:
    match Item.Data(1):
        case Item.Data():
            return 0
EOF

reject 'wrong number of variant payloads' <<'EOF'
union Item:
    Empty()
def main() -> int32:
    item: Item = Item.Empty(1)
    return 0
EOF

reject 'named arguments are only supported for record constructors' <<'EOF'
union Item:
    Data(n: int64)
def main() -> int32:
    item: Item = Item.Data(n=1)
    return 0
EOF

reject 'shadowing is forbidden' <<'EOF'
union Item:
    Data(n: int64)
def main() -> int32:
    n: int64 = 0
    match Item.Data(1):
        case Item.Data(n):
            return 0
EOF

reject 'unknown variable' <<'EOF'
union Item:
    Data(n: int64)
def main() -> int32:
    match Item.Data(1):
        case Item.Data(n):
            pass
    return int32(n)
EOF

reject "unknown variable 'local'" <<'EOF'
union Item:
    First()
    Second()
def main() -> int32:
    match Item.First():
        case Item.First():
            local: int64 = 1
        case Item.Second():
            return int32(local)
    return 0
EOF

reject "unknown variable 'local'" <<'EOF'
union Item:
    Only(n: int64)
def main() -> int32:
    match Item.Only(1):
        case Item.Only(n):
            local: int64 = n
    return int32(local)
EOF

reject 'this type does not support comparison' <<'EOF'
union Item:
    Empty()
def main() -> int32:
    if Item.Empty() == Item.Empty():
        return 1
    return 0
EOF

reject 'expected One, got Two' <<'EOF'
enum One:
    A
enum Two:
    A
def main() -> int32:
    if One.A == Two.A:
        return 1
    return 0
EOF

reject 'only numbers support ordering' <<'EOF'
enum Kind:
    A
def main() -> int32:
    if Kind.A < Kind.A:
        return 1
    return 0
EOF

reject 'cannot cast Kind to int32' <<'EOF'
enum Kind:
    A
def main() -> int32:
    return int32(Kind.A)
EOF

reject 'expected Kind, got int64' <<'EOF'
enum Kind:
    A
def main() -> int32:
    value: Kind = 0
    return 0
EOF

reject 'duplicate member' <<'EOF'
enum Kind:
    A
    A
EOF

reject 'duplicate member' <<'EOF'
union Item:
    A()
    A(n: int64)
EOF

reject 'duplicate payload field' <<'EOF'
union Item:
    A(n: int64, n: str)
EOF

reject 'void cannot be a payload type' <<'EOF'
union Item:
    A(n: void)
EOF

reject 'unknown type' <<'EOF'
union Item:
    A(n: Missing)
EOF

reject 'recursive value layout' <<'EOF'
union Item:
    A(n: Item)
EOF

reject 'recursive value layout' <<'EOF'
union Item:
    A(n: Box[2])
struct Box:
    item: Item
EOF

reject 'extern parameters must be scalar or ptr' <<'EOF'
enum Kind:
    A
extern def foreign(value: Kind) -> void
EOF

reject 'extern results must be scalar, ptr, or void' <<'EOF'
union Item:
    Empty()
extern def foreign() -> Item
EOF

reject 'duplicate declaration' <<'EOF'
enum Kind:
    A
struct Kind:
    pass
EOF

reject 'case belongs to a different type' <<'EOF'
import models
enum Kind:
    Number
    Text
def main() -> int32:
    match models.Kind.Number:
        case Kind.Number:
            return 0
EOF

reject 'pattern binding conflicts with a declaration or namespace' <<'EOF'
import models as data
def main() -> int32:
    match data.Item.Number(1):
        case data.Item.Number(data):
            return 0
        case data.Item.Text(s):
            return 0
        case data.Item.Empty():
            return 0
EOF

reject 'module namespace conflicts with a declaration' <<'EOF'
import models as Kind
enum Kind:
    A
EOF

reject "expected '<indent>'" <<'EOF'
enum Empty:
EOF

reject "expected '<indent>'" <<'EOF'
union Empty:
EOF

reject 'unknown member' <<'EOF'
enum Kind:
    A
def main() -> int32:
    kind: Kind = Kind.B
    return 0
EOF

reject 'match requires an enum or union' <<'EOF'
def main() -> int32:
    match 1:
        case Kind.A:
            return 0
EOF

reject 'shadowing is forbidden' <<'EOF'
union Item:
    Pair(a: int64, b: int64)
def main() -> int32:
    match Item.Pair(1, 2):
        case Item.Pair(n, n):
            return 0
EOF

reject 'expected int64, got str' <<'EOF'
union Item:
    Number(value: int64)
def main() -> int32:
    item: Item = Item.Number("wrong")
    return 0
EOF

reject 'extern results must be scalar, ptr, or void' <<'EOF'
enum Kind:
    A
extern def foreign() -> Kind
EOF

reject 'extern parameters must be scalar or ptr' <<'EOF'
union Item:
    Empty()
extern def foreign(item: Item) -> void
EOF

echo 'Passed typed enum, tagged union, and exhaustive match checks.'
