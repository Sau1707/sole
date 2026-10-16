#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-loops-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/loops.sole" <<'EOF'
import core


def bound(log: int64[], value: int64) -> int64:
    core.append(log, value)
    return value


def range(value: int64) -> int64:
    return value + 1


def main() -> int32:
    log: int64[] = []
    total: int64 = 0
    limit: int64 = 3
    for i in range(bound(log, -2), bound(log, limit)):
        total += i
        limit = 0
        i = 100
    if total != 0 || core.len(log) != 2 || log[0] != -2 || log[1] != 3:
        return 1
    for i in range(bound(log, 3)):
        total += i
    if total != 3 || core.len(log) != 3:
        return 2
    for i in range(-5):
        return 3
    for i in range(0):
        return 3
    for i in range(4, -2):
        return 4
    for i in range(-3, -3):
        return 5
    for i in range(-3, -1):
        total += i
    if total != -2:
        return 6
    count: int64 = 0
    for outer in range(4):
        for inner in range(5):
            if inner == 1:
                continue
            if inner == 3:
                break
            count += 1
        if outer == 1:
            continue
        if outer == 2:
            break
        count += 10
    if count != 16:
        return 7
    turn: int64 = 0
    while turn < 2:
        turn += 1
        for inner in range(3):
            if inner == 1:
                continue
            count += 1
        continue
    for outer in range(2):
        turn = 0
        while turn < 3:
            turn += 1
            if turn == 1:
                continue
            break
        count += turn
        continue
    if count != 24:
        return 8
    for edge in range(9223372036854775806, 9223372036854775807):
        if edge != 9223372036854775806:
            return 9
        continue
    for edge in range(-9223372036854775808, -9223372036854775807):
        if edge != -9223372036854775808:
            return 10
    for comma in range(0,):
        return 13
    for comma in range(2, 2,):
        return 14
    i: int64 = 7
    i += 2
    small: int8 = 127
    small += 1
    unsigned: uint64 = 18446744073709551615
    unsigned += 1
    real32: float32 = 1.5
    real32 += 2
    real64: float64 = 2.25
    real64 += 0.5
    if i != 9 || small != -128 || unsigned != 0 || real32 != 3.5 || real64 != 2.75:
        return 11
    text: str = "+="
    if text != "+=" || range(2) != 3:
        return 12
    return 0
EOF

"$compiler" syntax --grammar "$root/compiler/sole.ebnf" "$temporary/loops.sole"
"$compiler" check "$temporary/loops.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/loops.sole" "$optimize" -o "$temporary/program"
    timeout 10 "$temporary/program"
done

reject() {
    diagnostic=$1
    cat > "$temporary/bad.sole"
    for command in check build; do
        status=0
        "$compiler" "$command" "$temporary/bad.sole" > "$temporary/error" 2>&1 || status=$?
        if [ "$status" -ne 1 ] || ! grep -Fq "$diagnostic" "$temporary/error"; then
            cat "$temporary/error" >&2
            echo "FAIL: $command did not reject with: $diagnostic" >&2
            exit 1
        fi
    done
}

reject "unknown variable 'i'" <<'EOF'
def main() -> int32:
    for i in range(2):
        pass
    return int32(i)
EOF
reject 'shadowing is forbidden' <<'EOF'
def main() -> int32:
    i: int64 = 0
    for i in range(2):
        pass
    return 0
EOF
reject 'shadowing is forbidden' <<'EOF'
def main() -> int32:
    for i in range(2):
        for i in range(2):
            pass
    return 0
EOF
for typ in int32 uint64 float64 bool; do
    value=2
    if [ "$typ" = bool ]; then value=true; fi
    reject "expected int64, got $typ" <<EOF
def main() -> int32:
    bound: $typ = $value
    for i in range(bound):
        pass
    return 0
EOF
    reject "expected int64, got $typ" <<EOF
def main() -> int32:
    bound: $typ = $value
    for i in range(0, bound):
        pass
    return 0
EOF
done
reject 'expected int64, got float64' <<'EOF'
def main() -> int32:
    for i in range(1.5):
        pass
    return 0
EOF
reject "expected 'range'" <<'EOF'
def main() -> int32:
    values: int64[] = [1, 2]
    for i in values:
        pass
    return 0
EOF
reject "expected ')'" <<'EOF'
def main() -> int32:
    for i in range(0, 3, 1):
        pass
    return 0
EOF
reject '+= requires a numeric local identifier' <<'EOF'
struct Box:
    value: int64


def main() -> int32:
    box: Box = Box(1)
    box.value += 2
    return 0
EOF
reject '+= requires a numeric local identifier' <<'EOF'
def main() -> int32:
    values: int64[] = [1]
    values[0] += 2
    return 0
EOF
reject 'expected an identifier' <<'EOF'
def main() -> int32:
    value: int64 = 1
    (value) += 2
    return 0
EOF
reject '+= requires a numeric local identifier' <<'EOF'
def main() -> int32:
    value: int64 = 1
    value + value += 2
    return 0
EOF
reject '+= requires a numeric local identifier' <<'EOF'
def main() -> int32:
    value: str = "a"
    value += "b"
    return 0
EOF
reject 'expected int64, got bool' <<'EOF'
def main() -> int32:
    value: int64 = 1
    value += true
    return 0
EOF
reject 'expected float32, got float64' <<'EOF'
def main() -> int32:
    value: float32 = 1
    other: float64 = 2
    value += other
    return 0
EOF
reject '+= requires a numeric local identifier' <<'EOF'
class Box:
    value: int64

    def update(self) -> void:
        self += self


def main() -> int32:
    return 0
EOF
echo 'Passed range loops and numeric local += checks.'
