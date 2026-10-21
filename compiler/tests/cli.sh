#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
timeout_command=$(command -v timeout)
deadline_shell=$(command -v sh)
compile_timeout=${SOLE_TEST_COMPILE_TIMEOUT-60}
run_timeout=${SOLE_TEST_RUN_TIMEOUT-10}
for seconds in "$compile_timeout" "$run_timeout"; do
    case "$seconds" in
        ''|*[!0-9]*) echo 'FAIL: CLI deadlines must be positive integer seconds' >&2; exit 1 ;;
        *[1-9]*) ;;
        *) echo 'FAIL: CLI deadlines must be positive integer seconds' >&2; exit 1 ;;
    esac
done
hello="$root/compiler/tests/cases/001-compile_without_python_on_path/source/hello.sole"
imports="$root/compiler/tests/cases/111-standard_library/source/main.sole"
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-cli-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    if [ -f "$temporary/compile.log" ]; then cat "$temporary/compile.log" >&2; fi
    exit 1
}

bounded() {
    budget=$1
    shift
    result=0
    completion="$temporary/deadline-status"
    : > "$completion"
    "$timeout_command" --kill-after=1s "${budget}s" "$deadline_shell" -c '
        completion=$1
        shift
        "$@"
        result=$?
        printf "%s\n" "$result" > "$completion"
        exit "$result"
    ' sh "$completion" "$@" || result=$?
    if [ -s "$completion" ]; then
        IFS= read -r result < "$completion"
    else
        case "$result" in
            124|137) fail "command timed out after $budget seconds" ;;
            *) fail "deadline supervisor exited with status $result" ;;
        esac
    fi
    return "$result"
}

bounded "$compile_timeout" "$compiler" --version | grep -q 'sole 0.0.12' || fail version
SOLE_CC=/no/such/linker bounded "$compile_timeout" "$compiler" check "$hello" > "$temporary/compile.log" 2>&1 || fail 'check requires a linker'
for emit in llvm object; do
    bounded "$compile_timeout" "$compiler" build "$hello" --emit "$emit" -o "$temporary/hello.$emit" > "$temporary/compile.log" 2>&1 || fail "$emit emission"
    test -s "$temporary/hello.$emit" || fail "empty $emit output"
done
cp "$hello" "$temporary/protected.sole"
ln -s "$temporary/protected.sole" "$temporary/alias.sole"
for output in "$temporary/protected.sole" "$temporary/alias.sole"; do
    if bounded "$compile_timeout" "$compiler" build "$temporary/protected.sole" --emit llvm -o "$output" > "$temporary/compile.log" 2>&1; then
        fail 'source overwrite allowed'
    fi
    grep -q 'must not overwrite' "$temporary/compile.log" || fail 'source overwrite diagnostic'
done
cmp -s "$hello" "$temporary/protected.sole" || fail 'source changed'
for options in '--target wasm' '--export main' '--emit missing' '-O9'; do
    if bounded "$compile_timeout" "$compiler" check "$hello" $options > "$temporary/compile.log" 2>&1; then
        fail "invalid options accepted: $options"
    fi
done
if bounded "$compile_timeout" "$compiler" check "$temporary/missing.sole" > "$temporary/compile.log" 2>&1; then fail 'missing source accepted'; fi
printf 'def main() -> int32:\n    return missing\n' > "$temporary/bad.sole"
if bounded "$compile_timeout" "$compiler" check "$temporary/bad.sole" > "$temporary/compile.log" 2>&1; then fail 'unknown variable accepted'; fi
grep -q 'bad.sole:2' "$temporary/compile.log" || fail 'source location missing'
printf 'def main() -> int32:\n    return 7\n' > "$temporary/exit.sole"
status=0
bounded "$compile_timeout" "$compiler" run "$temporary/exit.sole" > "$temporary/compile.log" 2>&1 || status=$?
[ "$status" -eq 7 ] || fail 'run exit status'
for emit in llvm object; do
    if bounded "$compile_timeout" "$compiler" run "$temporary/exit.sole" --emit "$emit" -o "$temporary/not-run.$emit" > "$temporary/compile.log" 2>&1; then
        fail "run accepted $emit emission"
    fi
    grep -q 'run requires binary emission' "$temporary/compile.log" || fail 'run emission diagnostic'
    test ! -e "$temporary/not-run.$emit" || fail 'run emitted an unused artifact'
done

mkdir -p "$temporary/tools"
for tool in cc as ld; do ln -s "$(command -v "$tool")" "$temporary/tools/$tool"; done
PATH="$temporary/tools" bounded "$compile_timeout" "$compiler" build "$hello" -o "$temporary/hello" > "$temporary/compile.log" 2>&1 || fail 'build without interpreters'
bounded "$run_timeout" "$temporary/hello" > "$temporary/actual"
printf 'Hello from Sole!\n' > "$temporary/expected"
cmp -s "$temporary/expected" "$temporary/actual" || fail 'interpreter-free executable'

mkdir -p "$temporary/installed/bin" "$temporary/installed/share/sole"
install -m 755 "$compiler" "$temporary/installed/bin/sole"
compiler_prefix=$(dirname -- "$(dirname -- "$compiler")")
if [ -d "$compiler_prefix/lib/sole" ]; then
    mkdir -p "$temporary/installed/lib"
    cp -R "$compiler_prefix/lib/sole" "$temporary/installed/lib/"
fi
cp -R "$root/lib" "$temporary/installed/share/sole/"
mkdir -p "$temporary/installed/share/sole/compiler"
cp -R "$root/compiler/raw" "$root/compiler/runtime" "$temporary/installed/share/sole/compiler/"
mv "$temporary/installed" "$temporary/relocated"
unset SOLE_HOME SOLE_LIB
cd "$temporary"
PATH="$temporary/tools" bounded "$compile_timeout" "$temporary/relocated/bin/sole" build "$imports" -o "$temporary/imports" > "$temporary/compile.log" 2>&1 || fail 'relocated installation'
bounded "$run_timeout" "$temporary/imports" > "$temporary/actual"
printf '6\ntrue\nhahaha\n97\n' > "$temporary/expected"
cmp -s "$temporary/expected" "$temporary/actual" || fail 'relocated library'
echo 'Passed CLI checks and interpreter-free relocation.'
