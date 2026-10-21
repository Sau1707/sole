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

struct Box:
    value: int64

def read(box: Box) -> int64:
    return box.value

def add(value: int64, other: int64) -> int64:
    return value + other
EOF

cat > "$temporary/bridge.sole" <<'EOF'
import package.models as models

def make(value: int64) -> models.Point:
    return models.Point(models.add(value, 1))
EOF

cat > "$temporary/main.sole" <<'EOF'
import core
import core as helpers
import bridge
import string_array
import package.models
import package.models as models
import package.models as other
import runtime.system as system

struct Labels:
    sum: int64

def identity(point: models.Point) -> models.Point:
    return point

def main() -> int32:
    point: models.Point = identity(bridge.make(4))
    box: other.Box = models.Box(point.value)
    labels: Labels = Labels(3)
    labels.sum = labels.sum + 1
    numbers: int64[] = [1, 2, 3]
    if models.add(models.read(box), labels.sum) != 9 || core.len(numbers) != 3 || helpers.len(numbers) != 3:
        return 1
    if other.add(1, 2) != package.models.add(1, 2) || models.read(box) != 5:
        return 2
    if system.f64_bits(0.0) != 0:
        return 3
    if string_array.index_of(["a", "b", "c"], "b") != 1 || not string_array.contains(["a", "b"], "b"):
        return 4
    add: int64 = 2
    if models.add(add, 1) != 3:
        return 5
    text: str = "from package.models import Point"
    fromage: int32 = 0
    if text != "from package.models import Point":
        return 6
    return fromage
EOF

"$compiler" check "$temporary/main.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    timeout 10 "$temporary/program"
done

reject() {
    message=$1
    cat > "$temporary/reject.sole"
    for command in check build; do
        status=0
        "$compiler" "$command" "$temporary/reject.sole" -o "$temporary/program" > "$temporary/error" 2>&1 || status=$?
        if [ "$status" -ne 1 ] || ! grep -Fq "$message" "$temporary/error"; then
            cat "$temporary/error" >&2
            echo "FAIL: expected $command rejection: $message (status $status)" >&2
            exit 1
        fi
    done
}

reject "has no declaration 'missing'" <<'EOF'
import package.models as models
def main() -> int32:
    return int32(models.missing())
EOF
grep -Fq "$temporary/reject.sole:3:" "$temporary/error"

reject "cannot find module 'absent'" <<'EOF'
import absent
EOF
for module in wrappers.system system; do
    printf 'import %s\n' "$module" | reject "cannot find module '$module'"
    grep -Fq "$temporary/reject.sole:1:" "$temporary/error"
done

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

reject 'module namespace conflicts with a declaration: Point' <<'EOF'
import package.models as Point
struct Point:
    value: int64
EOF

for body in '    models: int64 = 1' '    for models in range(2):
        pass'; do
    printf 'import package.models as models\ndef main() -> int32:\n%s\n    return 0\n' "$body" |
        reject 'module namespace cannot be rebound: models'
done

reject 'module namespace cannot be rebound: models' <<'EOF'
import package.models as models
def score(models: int64) -> int64:
    return models
EOF

reject 'a module namespace is not a value' <<'EOF'
import package.models as models
def main() -> int32:
    models = 1
    return 0
EOF

reject 'imports are only allowed at module scope' <<'EOF'
def main() -> int32:
    import package.models
    return 0
EOF

for name in __sole_ __sole_hidden; do
    for source in "def $name() -> int32:
    return 0" "import package.models as $name" "import $name"; do
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
import bridge
def main() -> int32:
    point: bridge.Point = bridge.Point(1)
    return 0
EOF

reject "unknown function 'add'" <<'EOF'
import package.models
def main() -> int32:
    return int32(add(1, 2))
EOF

for statement in 'from' 'from package.models' 'from package.models import Point' \
    'from package.models import Point as P' 'from package.models import Point, Box' \
    'from package.models import *' 'from .package.models import Point' \
    'from absent import Point'; do
    printf '%s\n' "$statement" | reject 'named imports are not supported'
    grep -Fq "$temporary/reject.sole:1:" "$temporary/error"
done
reject 'named imports are not supported' <<'EOF'
def main() -> int32:
    from package.models import Point
    return 0
EOF
grep -Fq "$temporary/reject.sole:2:" "$temporary/error"

for statement in 'import' 'import package.models as' 'import package.models as def' \
    'import package.models,' 'import *' 'import .package.models' \
    'import (package.models)' 'import package.models, bridge'; do
    printf '%s\n' "$statement" | reject 'sole: error:'
done

cat > "$temporary/cycle.sole" <<'EOF'
import cycle as other
def value() -> int32:
    return 0
EOF
reject 'circular import' <<'EOF'
import cycle
EOF

cat > "$temporary/broken.sole" <<'EOF'
import package.models as models
def broken() -> int32:
    return missing
EOF
reject 'broken.sole:3:' <<'EOF'
import broken
EOF

echo 'Passed module imports, aliases, qualified names, and named-import rejection checks.'
