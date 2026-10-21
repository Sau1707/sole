#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-structs-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
export SOLE_HOME="$root" SOLE_LIB="$root/lib"

cat > "$temporary/main.sole" <<'EOF'
struct Data:
    value: int32

struct Empty:
    pass

def set(items: Data[], value: int32) -> void:
    items[0].value = value

def changed(item: Data) -> Data:
    item.value = 9
    return item

def main() -> int32:
    original: Data = Data(1)
    copy: Data = changed(original)
    empty: Empty = Empty()
    items: Data[] = [original]
    alias: Data[] = items
    set(alias, 4)
    if original.value != 1 || copy.value != 9 || items[0].value != 4:
        return 1
    return 0
EOF
"$compiler" syntax "$temporary/main.sole"
"$compiler" check "$temporary/main.sole"
for optimize in -O0 -O2; do
    "$compiler" build "$temporary/main.sole" "$optimize" -o "$temporary/program"
    "$temporary/program"
done
echo 'Passed struct value semantics and explicit shared array storage.'
