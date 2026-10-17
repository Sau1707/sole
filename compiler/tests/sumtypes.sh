#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-sumtypes-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cp "$root/compiler/tests/source-cases/sumtypes/models.sole" "$temporary/models.sole"

cp "$root/compiler/tests/source-cases/sumtypes/main.sole" "$temporary/main.sole"

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
