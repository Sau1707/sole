#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-classes-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

reject() {
    printf '%s\n' "$1" > "$temporary/main.sole"
    for command in check build; do
        status=0
        SOLE_HOME="$root" SOLE_LIB="$root/lib" "$compiler" "$command" "$temporary/main.sole" -o "$temporary/program" > "$temporary/error" 2>&1 || status=$?
        [ "$status" -eq 1 ] || { cat "$temporary/error"; echo "FAIL: $command accepted a methodless class (status $status)" >&2; exit 1; }
        grep -Fq 'classes must declare at least one method; use struct for data-only records' "$temporary/error"
        grep -Fq 'main.sole:1:' "$temporary/error"
    done
}

reject 'class Fields:
    value: int32'
reject 'class Empty:
    pass'
reject 'class Documented:
    """Only documentation."""'
reject 'class Fields:
    """Documented fields."""
    value: int32
    pass
def unrelated() -> void:
    pass'

cat > "$temporary/main.sole" <<'EOF'
struct Data:
    value: int32

struct Empty:
    pass

class Counter:
    """Methods and fields may appear in either order."""
    pass
    def set(self, value: int32) -> void:
        self.value = value
    value: int32

class MethodOnly:
    def get(self) -> int32:
        return 7

def main() -> int32:
    original: Data = Data(1)
    copy: Data = original
    copy.value = 2
    empty: Empty = Empty()
    counter: Counter = Counter(3)
    alias: Counter = counter
    alias.set(4)
    method: MethodOnly = MethodOnly()
    if original.value != 1 || copy.value != 2 || counter.value != 4 || method.get() != 7:
        return 1
    return 0
EOF
for optimize in -O0 -O2; do
    SOLE_HOME="$root" SOLE_LIB="$root/lib" "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    "$temporary/program"
done
SOLE_HOME="$root" "$compiler" syntax --grammar "$root/compiler/syntax/parser/sole.ebnf" "$temporary/main.sole"
echo 'Passed class method requirements and struct value semantics.'
