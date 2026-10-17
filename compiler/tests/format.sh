#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-format-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

check_formatting() {
    input=$1
    expected=$2
    cp "$input" "$temporary/original.sole"
    status=0
    "$compiler" format --check "$input" > "$temporary/log" 2>&1 || status=$?
    if cmp -s "$temporary/original.sole" "$expected"; then
        test "$status" -eq 0
    else
        test "$status" -eq 1
    fi
    cmp "$temporary/original.sole" "$input"
    "$compiler" format "$input" > "$temporary/log"
    cmp "$expected" "$input"
    "$compiler" format "$input" > "$temporary/log"
    test ! -s "$temporary/log"
    cmp "$expected" "$input"
    "$compiler" format --check "$input"
}

if "$compiler" format > "$temporary/log" 2>&1; then
    echo 'FAIL: format accepted missing paths' >&2
    exit 1
fi
grep -q 'Usage: sole format' "$temporary/log"
for argument in --check --unknown not-sole.txt; do
    if "$compiler" format "$argument" > "$temporary/log" 2>&1; then
        echo "FAIL: format accepted $argument without a source file" >&2
        exit 1
    fi
done

cp "$root/compiler/tests/format-cases/013/expected" "$temporary/input.sole"

cp "$root/compiler/tests/format-cases/022/source" "$temporary/strings.sole"

printf 'import core\r\ndef main() -> void:\r\n    # Body comment.\r\n    pass' > "$temporary/crlf.sole"
printf 'import core\r\n\r\n\r\ndef main() -> void:\r\n\r\n    # Body comment.\r\n    """TODO: Document this function."""\r\n    pass' > "$temporary/crlf-expected.sole"
"$compiler" format "$temporary/crlf.sole"
cmp "$temporary/crlf.sole" "$temporary/crlf-expected.sole"
"$compiler" format --check "$temporary/input.sole" "$temporary/strings.sole" "$temporary/crlf.sole"

printf 'import statistics\r\nimport math\r\nimport os' > "$temporary/imports-crlf.sole"
printf 'import os\r\nimport math\r\nimport statistics' > "$temporary/imports-crlf-expected.sole"
"$compiler" format "$temporary/imports-crlf.sole"
cmp "$temporary/imports-crlf.sole" "$temporary/imports-crlf-expected.sole"
"$compiler" format --check "$temporary/imports-crlf.sole"

for malformed in '"""unterminated' 'def broken(' 'def broken([)]'; do
    printf '%s\n' "$malformed" > "$temporary/bad.sole"
    cp "$temporary/bad.sole" "$temporary/original.sole"
    if "$compiler" format "$temporary/bad.sole"; then
        echo 'FAIL: malformed input accepted' >&2
        exit 1
    fi
    cmp "$temporary/bad.sole" "$temporary/original.sole"
done

awk 'BEGIN {
    print "import core\n\n\ndef first() -> void:\n    \"\"\"Print a nested expression.\"\"\""
    printf "    core.print("
    for (i = 0; i < 256; i++) printf "("
    printf "1"
    for (i = 0; i < 256; i++) printf ")"
    print ")\n    values: int32[] = [1]\n\n\ndef second() -> void:\n    \"\"\"Do nothing.\"\"\"\n    pass"
}' > "$temporary/nested.sole"
cp "$temporary/nested.sole" "$temporary/original.sole"
"$compiler" format --check "$temporary/nested.sole"
"$compiler" format "$temporary/nested.sole"
cmp "$temporary/nested.sole" "$temporary/original.sole"
for delimiters in '()[]([)]' '()[]]' '()[]('; do
    printf '%s\n' "$delimiters" > "$temporary/bad.sole"
    cp "$temporary/bad.sole" "$temporary/original.sole"
    if "$compiler" format "$temporary/bad.sole" > "$temporary/log" 2>&1; then
        echo "FAIL: reused delimiter stack accepted $delimiters" >&2
        exit 1
    fi
    cmp "$temporary/bad.sole" "$temporary/original.sole"
done

mkdir "$temporary/tools"
PATH="$temporary/tools" "$compiler" format --check "$temporary/input.sole"
count=0
for case in "$root"/compiler/tests/format-cases/*; do
    cp "$case/source" "$temporary/fixture.sole"
    if [ -f "$case/invalid" ]; then
        if "$compiler" format "$temporary/fixture.sole" > "$temporary/log" 2>&1; then
            echo "FAIL: invalid formatter case $case was accepted" >&2
            exit 1
        fi
        cmp "$case/source" "$temporary/fixture.sole"
    else
        check_formatting "$temporary/fixture.sole" "$case/expected"
    fi
    count=$((count + 1))
done

cat > "$temporary/executable.sole" <<'EOF'
import core
class Box:
    value: int32
    def read(self) -> int32:
        # Read the value.
        return self.value
def main() -> int32:
    box: Box = Box(42)
    # Print the result.
    core.print(box.read())
    return 0
EOF
"$compiler" format "$temporary/executable.sole" > "$temporary/log"
"$compiler" format --check "$temporary/executable.sole"
"$compiler" build "$temporary/executable.sole" -o "$temporary/executable" > "$temporary/log"
"$temporary/executable" > "$temporary/output"
printf '42\n' > "$temporary/expected-output"
cmp "$temporary/expected-output" "$temporary/output"

echo "Passed native formatter checks and $count migrated formatter cases."
