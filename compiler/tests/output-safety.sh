#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-output-safety-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
mkdir -p "$temporary/home" "$temporary/source" "$temporary/aliases" "$temporary/output" "$temporary/tmp"
cp -R "$root/lib" "$temporary/home/lib"
mkdir -p "$temporary/home/compiler"
cp -R "$root/compiler/raw" "$root/compiler/runtime" "$temporary/home/compiler/"
export SOLE_HOME="$temporary/home" SOLE_LIB="$temporary/home/lib" TMPDIR="$temporary/tmp"

fail() {
    echo "FAIL: $*" >&2
    if [ -f "$temporary/log" ]; then cat "$temporary/log" >&2; fi
    exit 1
}

compile() {
    timeout --kill-after=5 "${SOLE_TEST_COMPILE_TIMEOUT:-60}" "$compiler" "$@"
}

cat > "$temporary/source/main.sole" <<'EOF'
import dependency
import empty

def main() -> int32:
    return dependency.answer()
EOF
printf 'import leaf\n\ndef answer() -> int32:\n    return leaf.answer()\n' > "$temporary/source/dependency.sole"
printf 'def answer() -> int32:\n    return 0\n' > "$temporary/source/leaf.sole"
printf '# An imported module without emitted tokens.\n' > "$temporary/source/empty.sole"

for input in "$temporary/source/"*.sole "$temporary/home/compiler/runtime/native.ll" \
    "$temporary/home/compiler/runtime/core.ll" "$temporary/home/compiler/runtime/io.sole" \
    "$temporary/home/compiler/raw/c.sole"; do
    cp "$input" "$temporary/original"
    rm -f "$temporary/aliases/symlink" "$temporary/aliases/hardlink"
    ln -s "$input" "$temporary/aliases/symlink"
    ln "$input" "$temporary/aliases/hardlink"
    for output in "$input" "$temporary/aliases/symlink" "$temporary/aliases/hardlink"; do
        for emit in llvm object binary; do
            if compile build "$temporary/source/main.sole" --emit "$emit" -o "$output" > "$temporary/log" 2>&1; then
                fail "allowed $emit output to overwrite an input: $output"
            fi
            grep -q 'must not overwrite the source file' "$temporary/log" || fail 'input protection diagnostic'
            cmp -s "$input" "$temporary/original" || fail 'protected input changed'
        done
    done
done

cat > "$temporary/failing-linker" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        shift
        printf 'partial executable\n' > "$1"
        exit 1
    fi
    shift
done
exit 1
EOF
chmod +x "$temporary/failing-linker"
program="$temporary/output/program with ' quotes"
printf '#!/bin/sh\nexit 17\n' > "$program"
chmod 751 "$program"
cp -p "$program" "$temporary/previous"
if SOLE_CC="$temporary/failing-linker" compile build "$temporary/source/main.sole" -o "$program" > "$temporary/log" 2>&1; then
    fail 'failed linker reported success'
fi
grep -q 'linking failed' "$temporary/log" || fail 'link failure diagnostic'
cmp -s "$program" "$temporary/previous" || fail 'failed linking changed the existing executable'
test -x "$program" || fail 'failed linking changed executable permissions'
test -z "$(find "$temporary/output" -mindepth 1 -type d -print)" || fail 'failed linking leaked staging files'

if SOLE_CC="$temporary/failing-linker" compile run "$temporary/source/main.sole" > "$temporary/log" 2>&1; then
    fail 'failed run-link reported success'
fi
grep -q 'linking failed' "$temporary/log" || fail 'run-link failure diagnostic'
test -z "$(find "$temporary/tmp" -mindepth 1 -print)" || fail 'failed run-link leaked temporary artifacts'

cc -Wall -Wextra -Werror -shared -fPIC "$root/compiler/tests/backend-failure.c" -o "$temporary/backend-failure.so"
for command in build run; do
    if LD_PRELOAD="$temporary/backend-failure.so${LD_PRELOAD:+:$LD_PRELOAD}" \
        compile "$command" "$temporary/source/main.sole" -o "$program" > "$temporary/log" 2>&1; then
        fail 'backend failure reported success'
    fi
    grep -q 'injected object emission failure' "$temporary/log" || fail 'backend failure diagnostic'
    cmp -s "$program" "$temporary/previous" || fail 'backend failure changed the existing executable'
    test -z "$(find "$temporary/output" -mindepth 1 -type d -print)" || fail 'backend failure leaked staging files'
    test -z "$(find "$temporary/tmp" -mindepth 1 -print)" || fail 'backend failure leaked temporary files'
done

compile build "$temporary/source/main.sole" -o "$program" > "$temporary/log" 2>&1 || fail 'successful publication failed'
timeout --kill-after=5 "${SOLE_TEST_RUN_TIMEOUT:-10}" "$program" || fail 'published executable failed'
ln -s "$program" "$temporary/output/program-link"
compile build "$temporary/source/main.sole" -o "$temporary/output/program-link" > "$temporary/log" 2>&1 || fail 'symlink output failed'
test -L "$temporary/output/program-link" || fail 'publishing replaced the output symlink'
timeout --kill-after=5 "${SOLE_TEST_RUN_TIMEOUT:-10}" "$temporary/output/program-link" || fail 'symlink executable failed'

mkdir "$temporary/output/existing-directory"
if compile build "$temporary/source/main.sole" -o "$temporary/output/existing-directory" > "$temporary/log" 2>&1; then
    fail 'publication onto a directory succeeded'
fi
grep -q 'cannot publish executable' "$temporary/log" || fail 'publication failure diagnostic'
test -d "$temporary/output/existing-directory" || fail 'publication replaced a directory'
test "$(find "$temporary/output" -mindepth 1 -type d -print)" = "$temporary/output/existing-directory" || fail 'publication failure leaked staging files'
echo 'Passed input protection, atomic publication, and failure cleanup checks.'
