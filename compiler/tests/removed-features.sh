#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-removed-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

reject() {
    message=$1
    cat > "$temporary/main.sole"
    for command in check build; do
        status=0
        "$compiler" "$command" "$temporary/main.sole" -o "$temporary/program" > "$temporary/error" 2>&1 || status=$?
        test "$status" -eq 1
        grep -Fq "$message" "$temporary/error"
        grep -Fq 'main.sole:' "$temporary/error"
    done
}

for declaration in class enum union; do
    printf '%s Value:\n    pass\n' "$declaration" | reject 'expected a function or struct declaration'
done
reject 'structs cannot contain methods' <<'EOF'
struct Value:
    def read(self) -> int32:
        return 1
EOF
reject 'methods are not supported' <<'EOF'
def main() -> int32:
    return int32(1).abs()
EOF
reject 'expected an expression' <<'EOF'
def main() -> int32:
    match true:
        case true:
            return 0
EOF
reject 'expected an expression' <<'EOF'
def main() -> int32:
    return lambda x: x
EOF
reject 'recursive value layout' <<'EOF'
struct First:
    second: Second[1]
struct Second:
    first: First
EOF
echo 'Passed removed-feature rejection and recursive struct layout checks.'
