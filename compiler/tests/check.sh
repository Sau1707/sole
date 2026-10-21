#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-check-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

for command in build check run; do
    status=0
    "$compiler" "$command" > "$temporary/error" 2>&1 || status=$?
    if [ "$status" -ne 1 ]; then
        echo "FAIL: $command accepted missing arguments (status $status)" >&2
        exit 1
    fi
    grep -Fq 'Usage: sole build|check|run' "$temporary/error"
done

reject() {
    printf '%s\n' "$1" > "$temporary/bad.sole"
    for command in check build; do
        status=0
        "$compiler" "$command" "$temporary/bad.sole" -o "$temporary/program" > "$temporary/error" 2>&1 || status=$?
        if [ "$status" -ne 1 ]; then
            cat "$temporary/error" >&2
            echo "FAIL: $command returned $status for: $1" >&2
            exit 1
        fi
        grep -Fq 'sole: error:' "$temporary/error"
    done
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
reject 'class Value:
    value: int32'
reject 'class Empty:
    pass'
reject 'class Documented:
    """Only documentation."""'
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
struct Pair:
    first: int64
    second: int64


def main() -> int32:
    pair: Pair = Pair(1, 2)
    total: int64 = 0
    for i in range(0, pair.second):
        total = total + i
    return int32(total)
EOF
SOLE_CC=/no/such/linker "$compiler" check "$temporary/features.sole" -o "$temporary/not-emitted" > "$temporary/output"
grep -Fxq "$temporary/features.sole: OK" "$temporary/output"
test ! -e "$temporary/not-emitted"
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

reject 'pass'
reject '"""unterminated'
reject 'def broken('
reject 'def broken([)]'
reject 'def main() -> int32:
    return missing_name'
grep -Fq "unknown variable 'missing_name'" "$temporary/error"
grep -Fq "$temporary/bad.sole:2:" "$temporary/error"
reject 'def main() -> int32:
    return "wrong"'
grep -Fq 'expected int32, got str' "$temporary/error"
reject 'import absent_check_dependency'
grep -Fq "cannot find module 'absent_check_dependency'" "$temporary/error"

mkdir "$temporary/猫"
cat > "$temporary/猫/dependency.sole" <<'EOF'
def broken() -> int32:
    return missing_name
EOF
cat > "$temporary/猫/main.sole" <<'EOF'
import dependency

def main() -> int32:
    return dependency.broken()
EOF
ln -s "$temporary/猫/main.sole" "$temporary/entry.sole"
for command in check build; do
    status=0
    "$compiler" "$command" "$temporary/entry.sole" -o "$temporary/program" > "$temporary/error" 2>&1 || status=$?
    test "$status" -eq 1
    grep -Fq "$temporary/猫/dependency.sole:2: unknown variable 'missing_name'" "$temporary/error"
done

for arguments in 'syntax' 'syntax --grammar' 'format' 'format --check'; do
    status=0
    "$compiler" $arguments "$temporary/features.sole" > "$temporary/error" 2>&1 || status=$?
    test "$status" -eq 1
    grep -Fq "unknown command: ${arguments%% *}" "$temporary/error"
done
status=0
"$compiler" check "$temporary/features.sole" --grammar missing.ebnf > "$temporary/error" 2>&1 || status=$?
test "$status" -eq 1
grep -Fq 'unknown option: --grammar' "$temporary/error"
echo 'Passed unified check/build rejection, semantic validation, and check-only behavior.'
