#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-process-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

${CC:-cc} -std=gnu11 -Wall -Wextra -Werror \
    "$root/compiler/tests/process.c" "$root/lib/runtime/system.c" \
    -o "$temporary/process"
"$temporary/process" "$temporary/no-shebang"
echo 'Passed process runtime checks.'

compiler=$(command -v "${SOLE_COMPILER:-sole}")
export SOLE_HOME="$root" SOLE_LIB="$root/lib"
SOLE_REAL_CC=$(command -v "${CC:-cc}")
export SOLE_REAL_CC
cat > "$temporary/linker's tool" <<'EOF'
#!/bin/sh
exec "$SOLE_REAL_CC" "$@"
EOF
chmod +x "$temporary/linker's tool"
cat > "$temporary/exit program.sole" <<'EOF'
import core
def main() -> int32:
    return 23
EOF
status=0
SOLE_CC="$temporary/linker's tool" "$compiler" run "$temporary/exit program.sole" > "$temporary/log" 2>&1 || status=$?
test "$status" -eq 23 || { cat "$temporary/log" >&2; exit 1; }
cat > "$temporary/signal.sole" <<'EOF'
import core
extern def raise(signal: int32) -> int32
def main() -> int32:
    raise(15)
    return 0
EOF
status=0
"$compiler" run "$temporary/signal.sole" > "$temporary/log" 2>&1 || status=$?
test "$status" -eq 143 || { cat "$temporary/log" >&2; exit 1; }
echo 'Passed process CLI status and quoted linker path checks.'
