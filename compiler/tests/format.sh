#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
formatter() {
    "$compiler" format "$@"
}
. "$root/compiler/tests/temp-root.sh"
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

cat > "$temporary/imports.sole" <<'EOF'
import frontend.lexer as lexer
import math
import core # Keep this long comment with core, without counting it for sorting.
import os

import strings
import env
# Separate group.
import statistics
import files


def main() -> str:
    return """import statistics
import os
"""
EOF
cat > "$temporary/imports-expected.sole" <<'EOF'
import os
import math
import core # Keep this long comment with core, without counting it for sorting.
import frontend.lexer as lexer

import env
import strings
# Separate group.
import files
import statistics


def main() -> str:
    return """import statistics
import os
"""
EOF
cp "$temporary/imports.sole" "$temporary/original.sole"
if formatter --check "$temporary/imports.sole"; then
    echo 'FAIL: --check accepted unsorted imports' >&2
    exit 1
fi
cmp "$temporary/imports.sole" "$temporary/original.sole"
formatter "$temporary/imports.sole"
cmp "$temporary/imports.sole" "$temporary/imports-expected.sole"
formatter --check "$temporary/imports.sole"
formatter "$temporary/imports.sole"
cmp "$temporary/imports.sole" "$temporary/imports-expected.sole"

printf 'import statistics\r\nimport math\r\nimport os' > "$temporary/imports-crlf.sole"
printf 'import os\r\nimport math\r\nimport statistics' > "$temporary/imports-crlf-expected.sole"
formatter "$temporary/imports-crlf.sole"
cmp "$temporary/imports-crlf.sole" "$temporary/imports-crlf-expected.sole"
formatter --check "$temporary/imports-crlf.sole"

for malformed in '"""unterminated' 'def broken(' 'def broken([)]'; do
    printf '%s\n' "$malformed" > "$temporary/bad.sole"
    cp "$temporary/bad.sole" "$temporary/original.sole"
    if formatter "$temporary/bad.sole"; then
        echo 'FAIL: malformed input accepted' >&2
        exit 1
    fi
    cmp "$temporary/bad.sole" "$temporary/original.sole"
done

awk 'BEGIN {
    print "import core\n\n\ndef first() -> void:"
    printf "    core.print("
    for (i = 0; i < 256; i++) printf "("
    printf "1"
    for (i = 0; i < 256; i++) printf ")"
    print ")\n    values: int32[] = [1]\n\n\ndef second() -> void:\n    pass"
}' > "$temporary/nested.sole"
cp "$temporary/nested.sole" "$temporary/original.sole"
formatter --check "$temporary/nested.sole"
formatter "$temporary/nested.sole"
cmp "$temporary/nested.sole" "$temporary/original.sole"
for delimiters in '()[]([)]' '()[]]' '()[]('; do
    printf '%s\n' "$delimiters" > "$temporary/bad.sole"
    cp "$temporary/bad.sole" "$temporary/original.sole"
    if formatter "$temporary/bad.sole" > "$temporary/log" 2>&1; then
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
