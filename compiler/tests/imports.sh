#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-imports-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"
mkdir -p "$temporary/package"

cat > "$temporary/package/models.sole" <<'EOF'
struct Point:
    value: int64


class Box:
    value: int64

    def read(self) -> int64:
        return self.value


enum Direction:
    Left
    Right


union Item:
    Value(value: int64)
    Empty()


def add(value: int64, other: int64) -> int64:
    return value + other
EOF

cat > "$temporary/bridge.sole" <<'EOF'
from package.models import Point, add


def make(value: int64) -> Point:
    return Point(add(value, 1))
EOF

cat > "$temporary/main.sole" <<'EOF'
import package.models as models
from package.models import Point as P, Box, Direction as D, Item as I
from package.models import add as sum
from package.models import add as other_sum
from core import len as size
from core import len
from bridge import make
from wrappers.system import sole_rt_f64_bits as bits
from math import min as minimum, clamp


struct Labels:
    sum: int64


class Methods:
    value: int64

    def sum(self) -> int64:
        return self.value


union Labeled:
    sum(sum: int64)
    Empty()


enum LabeledEnum:
    sum


def identity(point: P) -> P:
    return point


def main() -> int32:
    point: P = identity(make(4))
    box: Box = Box(value=point.value)
    labels: Labels = Labels(sum=3)
    methods: Methods = Methods(value=2)
    labeled: Labeled = Labeled.sum(1)
    labeled_enum: LabeledEnum = LabeledEnum.sum
    labels.sum = labels.sum + 1
    numbers: int64[] = [1, 2, 3]
    if sum(box.read(), labels.sum) != 9 || size(numbers) != 3 || len(numbers) != 3:
        return 1
    if other_sum(1, 2) != models.add(1, 2) || methods.sum() != 2:
        return 2
    if bits(0.0) != 0:
        return 6
    if minimum(2, 3) != 2 || clamp(9, 0, 4) != 4:
        return 7
    item: I = I.Value(point.value)
    direction: D = D.Left
    match item:
        case I.Value(value):
            match direction:
                case D.Left:
                    if value != 5:
                        return 3
                case D.Right:
                    return 4
        case I.Empty():
            return 5
    return 0
EOF

"$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole" "$temporary/bridge.sole"
"$compiler" check "$temporary/main.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    timeout 10 "$temporary/program"
done

reject() {
    message=$1
    cat > "$temporary/reject.sole"
    status=0
    "$compiler" check "$temporary/reject.sole" > "$temporary/error" 2>&1 || status=$?
    if [ "$status" -ne 1 ] || ! grep -Fq "$message" "$temporary/error"; then
        cat "$temporary/error" >&2
        echo "FAIL: expected import rejection: $message (status $status)" >&2
        exit 1
    fi
}

reject "has no declaration 'missing'" <<'EOF'
from package.models import missing
def main() -> int32:
    return 0
EOF
grep -Fq "$temporary/reject.sole:1:" "$temporary/error"

reject "cannot find module 'absent'" <<'EOF'
from absent import Point
EOF

reject "duplicate import 'P'" <<'EOF'
from package.models import Point as P, Box as P
EOF

reject "duplicate import 'Point'" <<'EOF'
from package.models import Point
from package.models import Point
EOF

reject "duplicate import 'package.models'" <<'EOF'
import package.models
import package.models
EOF
grep -Fq "$temporary/reject.sole:2:" "$temporary/error"

for alias in first last; do
    printf 'import package.models as first\nimport package.models as last\nimport package.models as %s\n' "$alias" |
        reject "duplicate import '$alias'"
    grep -Fq "$temporary/reject.sole:3:" "$temporary/error"
done

reject 'import conflicts with a declaration: Point' <<'EOF'
from package.models import Point
struct Point:
    value: int64
EOF

reject 'import conflicts with a declaration: add' <<'EOF'
def add() -> int32:
    return 0
from package.models import add
EOF

for imports in 'import package.models as Point
from package.models import Point' 'from package.models import Point as package
import package.models'; do
    printf '%s\n' "$imports" | reject 'import conflicts with a module namespace:'
done

for body in '    Point: int64 = 1' '    Point = 1' '    Point += 1' '    for Point in range(2):
        pass'; do
    printf 'from package.models import Point\ndef main() -> int32:\n%s\n    return 0\n' "$body" |
        reject 'imported name cannot be rebound or shadowed: Point'
done

reject 'imported name cannot be rebound or shadowed: Point' <<'EOF'
from package.models import Point
def main(Point: int64) -> int32:
    return 0
EOF

reject 'pattern binding conflicts' <<'EOF'
from package.models import Point, Item
def score(item: Item) -> int64:
    match item:
        case Item.Value(Point):
            return 0
        case Item.Empty():
            return 1
EOF

reject 'imports are only allowed at module scope' <<'EOF'
def main() -> int32:
    from package.models import Point
    return 0
EOF

reject 'imported name cannot be rebound or shadowed: Point' <<'EOF'
from package.models import Point
class Box:
    def read(self, Point: int64) -> int64:
        return 0
EOF

reject 'expected an import name or alias' <<'EOF'
from package.models import Point as def
EOF

for name in __sole_ __sole_hidden; do
    for source in "def $name() -> int32:
    return 0" "import package.models as $name" "from package.models import Point as $name"; do
        printf '%s\n' "$source" | reject "names beginning with '__sole_' are reserved"
    done
done

cat > "$temporary/prefix.sole" <<'EOF'
import package.models as __sole
def main() -> int32:
    value: __sole.Point = __sole.Point(1)
    return int32(value.value - 1)
EOF
"$compiler" check "$temporary/prefix.sole"

reject "has no declaration 'Point'" <<'EOF'
from bridge import Point
EOF

reject "has no declaration 'Point'" <<'EOF'
import bridge
def main() -> int32:
    point: bridge.Point = bridge.Point(1)
    return 0
EOF

reject 'unknown variable' <<'EOF'
from package.models import Point
def main() -> int32:
    value: int64 = package.models.add(1, 2)
    return 0
EOF

for statement in 'from' 'from package.models' 'from package.models import' \
    'from package.models import Point,' 'from package.models import Point as' \
    'from package.models import *' 'from .package.models import Point' \
    'from package.models import (Point)' 'from package.models import Point.Box'; do
    printf '%s\n' "$statement" > "$temporary/main.sole"
    if "$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole" > "$temporary/error" 2>&1; then
        echo "FAIL: grammar accepted $statement" >&2
        exit 1
    fi
    reject 'sole: error:' < "$temporary/main.sole"
done

cat > "$temporary/cycle.sole" <<'EOF'
from cycle import value as other
def value() -> int32:
    return 0
EOF
reject 'circular import' <<'EOF'
from cycle import value
EOF

cat > "$temporary/broken.sole" <<'EOF'
from package.models import Point
def broken() -> int32:
    return missing
EOF
reject 'broken.sole:3:' <<'EOF'
from broken import broken
EOF

echo 'Passed named import tests.'
