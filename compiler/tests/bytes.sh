#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-bytes-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/bytes.sole" <<'EOF'
import core


def identity(value: uint8) -> uint8:
    return value


def main() -> int32:
    b: uint8 = b'A'
    bytes: uint8[] = [b' ', b'\n', b'\r', b'\t', b'\0', b'\\', b'\'', b'"', b"\"", b"'", b'\"']
    expected: uint8[] = [32, 10, 13, 9, 0, 92, 39, 34, 34, 39, 34]
    i: int64 = 0
    while i < core.len(bytes):
        if bytes[i] != expected[i]:
            return 1
        i = i + 1
    if b != 65 || identity(b"Z") != 90:
        return 2
    if identity(b')') != 41 || identity(b',') != 44:
        return 3
    if b'(' != 40 || b'[' != 91 || b'#' != 35 || b'+' != 43:
        return 4
    if b'A' + 1 != 66 || int32(b'A') != 65:
        return 5
    text: str = "b'x'"
    ordinary: str = 'A'
    if core.len(text) != 4 || ordinary[0] != b'A':
        return 6
    core.print(b)
    return 0
EOF
"$compiler" syntax --grammar "$root/compiler/sole.ebnf" "$temporary/bytes.sole"
"$compiler" check "$temporary/bytes.sole"
printf '65\n' > "$temporary/expected"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/bytes.sole" "$optimize" -o "$temporary/program"
    "$temporary/program" > "$temporary/actual"
    cmp "$temporary/expected" "$temporary/actual"
done

reject() {
    command=$1
    literal=$2
    diagnostic=$3
    printf 'def main() -> uint8:\n    return %s\n' "$literal" > "$temporary/bad.sole"
    status=0
    "$compiler" "$command" "$temporary/bad.sole" > "$temporary/error" 2>&1 || status=$?
    if [ "$status" -ne 1 ]; then
        cat "$temporary/error" >&2
        echo "FAIL: $command returned $status for $literal" >&2
        exit 1
    fi
    grep -Fq "$diagnostic" "$temporary/error"
}

for command in syntax check build; do
    for literal in "b''" 'b""' "b'ab'" "b'é'" "b'🙂'" "b'\n\t'"; do
        reject "$command" "$literal" 'byte literal must contain exactly one byte at line 2'
    done
    reject "$command" "b'''A'''" 'byte literals cannot be triple-quoted at line 2'
    reject "$command" 'b"""A"""' 'byte literals cannot be triple-quoted at line 2'
    reject "$command" "b'\x41'" 'unsupported byte literal escape at line 2'
    reject "$command" "b'A" 'unterminated byte literal at line 2'
    reject "$command" 'b"A' 'unterminated byte literal at line 2'
    reject "$command" "b'
'" 'unterminated byte literal at line 2'
done

for command in check build; do
    printf 'def main() -> int32:\n    return b"A"\n' > "$temporary/type.sole"
    status=0
    "$compiler" "$command" "$temporary/type.sole" > "$temporary/error" 2>&1 || status=$?
    test "$status" -eq 1
    grep -Fq 'expected int32, got uint8; use an explicit cast' "$temporary/error"
    reject "$command" 'b "A"' "unknown variable 'b'"
done

# Literal contents must not be consumed as grammar punctuation.
printf 'program = "(", NEWLINE, EOF;\n' > "$temporary/punctuation.ebnf"
printf "b'('\n" > "$temporary/punctuation.sole"
status=0
"$compiler" syntax --grammar "$temporary/punctuation.ebnf" "$temporary/punctuation.sole" > "$temporary/error" 2>&1 || status=$?
test "$status" -eq 1
grep -Fq 'error' "$temporary/error"

cp "$temporary/bytes.sole" "$temporary/original.sole"
"$compiler" format --check "$temporary/bytes.sole"
"$compiler" format "$temporary/bytes.sole"
cmp "$temporary/original.sole" "$temporary/bytes.sole"
echo 'Passed byte literal execution, validation, syntax, and formatting checks.'
