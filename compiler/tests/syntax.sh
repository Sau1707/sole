#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=${SOLE_COMPILER:-"$root/.build/sole"}
temp_root=${TMPDIR:-/tmp}
if [ -z "${TMPDIR:-}" ] && [ -d /tmp/opencode ]; then temp_root=/tmp/opencode; fi
temporary=$(mktemp -d "$temp_root/sole-syntax-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

cp "$root/compiler/tests/syntax.sole" "$temporary/main.sole"
ln -s "$root/compiler/frontend" "$temporary/frontend"
SOLE_HOME="$root" "$compiler" build "$temporary/main.sole" -o "$temporary/syntax"

if [ "$#" -gt 0 ]; then
    "$temporary/syntax" "$root/sole.ebnf" "$@"
    exit 0
fi

find "$root/compiler" "$root/lib" -path "$root/compiler/tests" -prune -o -type f -name '*.sole' \
    -exec "$temporary/syntax" "$root/sole.ebnf" {} +
if [ -d "$root/examples" ]; then
    find "$root/examples" -type f -name '*.sole' -exec "$temporary/syntax" "$root/sole.ebnf" {} +
fi
"$temporary/syntax" "$root/sole.ebnf" "$root/compiler/tests/syntax.sole"
for fixture in "$root"/compiler/tests/cases/*; do
    case $(cat "$fixture/mode") in reject-*) continue ;; esac
    find "$fixture" -type f -name '*.sole' -exec "$temporary/syntax" "$root/sole.ebnf" {} +
done

reject() {
    printf '%s\n' "$1" > "$temporary/bad.sole"
    if "$temporary/syntax" "$root/sole.ebnf" "$temporary/bad.sole" > "$temporary/error" 2>&1; then
        echo "FAIL: grammar accepted: $1" >&2
        exit 1
    fi
    grep -q 'error' "$temporary/error"
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
    value += 2'
reject 'def main() -> int32:
    for value in values:
        pass'
reject 'struct Value:
    def get(self) -> int32:
        return 1'
reject 'def main() -> int32:
    return 0;'
reject 'import core as return'
reject 'def main() -> int32:
    return "return" +'

# Prove that the file, rather than a hard-coded Sole parser, drives acceptance.
printf 'program = "pass", NEWLINE, EOF;\n' > "$temporary/minimal.ebnf"
printf 'pass\n' > "$temporary/pass.sole"
"$temporary/syntax" "$temporary/minimal.ebnf" "$temporary/pass.sole"
if "$temporary/syntax" "$root/sole.ebnf" "$temporary/pass.sole" > "$temporary/error" 2>&1; then
    echo 'FAIL: Sole grammar accepted a module-level pass' >&2
    exit 1
fi
printf 'program = missing;\n' > "$temporary/invalid.ebnf"
if "$temporary/syntax" "$temporary/invalid.ebnf" "$temporary/pass.sole" > "$temporary/error" 2>&1; then
    echo 'FAIL: undefined grammar rule accepted' >&2
    exit 1
fi
grep -q 'unknown grammar rule missing' "$temporary/error"
echo 'Passed EBNF syntax checks, rejection cases, and grammar-driven acceptance.'
