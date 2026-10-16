#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=${SOLE_COMPILER:-"$root/.build/sole"}
formatter() {
    "$compiler" format "$@"
}
temp_root=${TMPDIR:-/tmp}
if [ -z "${TMPDIR:-}" ] && [ -d /tmp/opencode ]; then temp_root=/tmp/opencode; fi
temporary=$(mktemp -d "$temp_root/sole-format-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

if formatter > "$temporary/log" 2>&1; then
    echo 'FAIL: format accepted missing paths' >&2
    exit 1
fi
grep -q 'Usage: sole format' "$temporary/log"
for argument in --check --unknown not-sole.txt; do
    if formatter "$argument" > "$temporary/log" 2>&1; then
        echo "FAIL: format accepted $argument without a source file" >&2
        exit 1
    fi
done

printf 'import core\n# Entry point.\ndef first() -> void:\n    pass\n\n\n\n\ndef second() -> void:\n    pass' > "$temporary/input.sole"
printf 'import core\n\n\n# Entry point.\ndef first() -> void:\n    pass\n\n\ndef second() -> void:\n    pass' > "$temporary/expected.sole"
cp "$temporary/input.sole" "$temporary/original.sole"
if formatter --check "$temporary/input.sole"; then
    echo 'FAIL: --check accepted unformatted input' >&2
    exit 1
fi
cmp "$temporary/input.sole" "$temporary/original.sole"
formatter "$temporary/input.sole"
cmp "$temporary/input.sole" "$temporary/expected.sole"
formatter --check "$temporary/input.sole"
formatter "$temporary/input.sole"
cmp "$temporary/input.sole" "$temporary/expected.sole"

cat > "$temporary/strings.sole" <<'EOF'
import core


class Box:
    value: int32
    def read(self) -> int32:
        return self.value


def first(
    value: int32
) -> str:
    return """literal text
def fake() -> void:



class Fake:
"""


extern def second() -> void
EOF
cp "$temporary/strings.sole" "$temporary/original.sole"
formatter --check "$temporary/strings.sole"
formatter "$temporary/strings.sole"
cmp "$temporary/strings.sole" "$temporary/original.sole"

printf 'import core\r\ndef main() -> void:\r\n    pass' > "$temporary/crlf.sole"
printf 'import core\r\n\r\n\r\ndef main() -> void:\r\n    pass' > "$temporary/crlf-expected.sole"
formatter "$temporary/crlf.sole"
cmp "$temporary/crlf.sole" "$temporary/crlf-expected.sole"
formatter --check "$temporary/input.sole" "$temporary/strings.sole" "$temporary/crlf.sole"

for malformed in '"""unterminated' 'def broken(' 'def broken([)]'; do
    printf '%s\n' "$malformed" > "$temporary/bad.sole"
    cp "$temporary/bad.sole" "$temporary/original.sole"
    if formatter "$temporary/bad.sole"; then
        echo 'FAIL: malformed input accepted' >&2
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
        if formatter "$temporary/fixture.sole" > "$temporary/log" 2>&1; then
            echo "FAIL: invalid formatter case $case was accepted" >&2
            exit 1
        fi
        cmp "$case/source" "$temporary/fixture.sole"
    else
        status=0
        formatter --check "$temporary/fixture.sole" > "$temporary/log" 2>&1 || status=$?
        if cmp -s "$case/source" "$case/expected"; then
            test "$status" -eq 0
        else
            test "$status" -eq 1
        fi
        cmp "$case/source" "$temporary/fixture.sole"
        formatter "$temporary/fixture.sole" > "$temporary/log"
        cmp "$case/expected" "$temporary/fixture.sole"
        formatter "$temporary/fixture.sole" > "$temporary/log"
        test ! -s "$temporary/log"
        formatter --check "$temporary/fixture.sole"
    fi
    count=$((count + 1))
done
echo "Passed native formatter checks and $count migrated formatter cases."
