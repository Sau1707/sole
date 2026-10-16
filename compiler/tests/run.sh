#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=$(command -v "${SOLE_COMPILER:-sole}")
hello="$root/compiler/tests/cases/001-compile_without_python_on_path/source/hello.sole"
imports="$root/compiler/tests/cases/111-standard_library/source/main.sole"
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-tests-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
count=0

fail() {
    echo "FAIL: $*" >&2
    if [ -f "$temporary/compile.log" ]; then cat "$temporary/compile.log" >&2; fi
    exit 1
}

for case in "$root"/compiler/tests/cases/*; do
    mode=$(cat "$case/mode")
    case "$mode" in
        run|trap|exit|reject-build|reject-check) ;;
        *) fail "$(basename "$case") unknown fixture mode: $mode" ;;
    esac
    work="$temporary/case"
    rm -rf -- "$work"
    mkdir -p "$work/data/0" "$work/data/1"
    cp -R "$case/source" "$work/source"
    find "$work/source" -type f -name '*.sole' | while IFS= read -r source; do
        sed "s|@CASE_ROOT@|$work/source|g; s|@DATA_ROOT@|$work/data|g" "$source" > "$source.tmp"
        mv "$source.tmp" "$source"
    done
    entry=$(cat "$case/entry")
    optimize=$(cat "$case/optimize")
    command=build
    case "$mode" in reject-check) command=check ;; esac
    library="$root/lib"
    if [ -f "$case/library-override" ]; then library="$case/library"; fi
    module_env=
    if [ -f "$case/module-env" ]; then module_env=$(cat "$case/module-env"); fi
    status=0
    SOLE_HOME="$root" SOLE_LIB="$library" SOLE_MODULE_TEST="$module_env" \
        "$compiler" "$command" "$work/source/$entry" "$optimize" -o "$work/program" > "$temporary/compile.log" 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        case "$mode" in reject-*) fail "$(basename "$case") was accepted" ;; esac
    else
        case "$mode" in
            reject-*)
                [ "$status" -eq 1 ] || fail "$(basename "$case") compiler exited with status $status, expected 1"
                grep -Fq 'sole: error: ' "$temporary/compile.log" || fail "$(basename "$case") has no source diagnostic"
                if [ -f "$case/diagnostic" ]; then
                    grep -Fq -f "$case/diagnostic" "$temporary/compile.log" || fail "$(basename "$case") diagnostic differs"
                fi
                ;;
            *) fail "$(basename "$case") did not compile" ;;
        esac
    fi
    case "$mode" in
        run)
            SOLE_MODULE_TEST="$module_env" "$work/program" > "$temporary/actual" 2> "$temporary/run.log" || fail "$(basename "$case") did not run"
            cmp -s "$case/expected" "$temporary/actual" || fail "$(basename "$case") output differs"
            ;;
        trap)
            status=0
            "$work/program" > "$temporary/actual" 2> "$temporary/run.log" || status=$?
            [ "$status" -gt 128 ] || fail "$(basename "$case") expected a trap signal, got status $status"
            signal=$(kill -l "$status" 2>/dev/null || :)
            case "$signal" in
                ILL|SIGILL|TRAP|SIGTRAP) ;;
                *) fail "$(basename "$case") expected a trap signal, got status $status" ;;
            esac
            ;;
        exit)
            status=0
            "$work/program" > "$temporary/actual" 2> "$temporary/run.log" || status=$?
            expected_status=$(cat "$case/status")
            [ "$status" -eq "$expected_status" ] || fail "$(basename "$case") exit status differs"
            cmp -s "$case/expected" "$temporary/actual" || fail "$(basename "$case") output differs"
            ;;
    esac
    count=$((count + 1))
done

"$compiler" --version | grep -q 'sole 0.0.4' || fail version
SOLE_CC=/no/such/linker "$compiler" check "$hello" > "$temporary/compile.log" 2>&1 || fail 'check requires a linker'
for emit in llvm object; do
    "$compiler" build "$hello" --emit "$emit" -o "$temporary/hello.$emit" > "$temporary/compile.log" 2>&1 || fail "$emit emission"
    test -s "$temporary/hello.$emit" || fail "empty $emit output"
done
cp "$hello" "$temporary/protected.sole"
ln -s "$temporary/protected.sole" "$temporary/alias.sole"
for output in "$temporary/protected.sole" "$temporary/alias.sole"; do
    if "$compiler" build "$temporary/protected.sole" --emit llvm -o "$output" > "$temporary/compile.log" 2>&1; then
        fail 'source overwrite allowed'
    fi
    grep -q 'must not overwrite' "$temporary/compile.log" || fail 'source overwrite diagnostic'
done
cmp -s "$hello" "$temporary/protected.sole" || fail 'source changed'
for options in '--target wasm' '--export main' '--emit missing' '-O9'; do
    if "$compiler" check "$hello" $options > "$temporary/compile.log" 2>&1; then
        fail "invalid options accepted: $options"
    fi
done
if "$compiler" check "$temporary/missing.sole" > "$temporary/compile.log" 2>&1; then fail 'missing source accepted'; fi
printf 'def main() -> int32:\n    return missing\n' > "$temporary/bad.sole"
if "$compiler" check "$temporary/bad.sole" > "$temporary/compile.log" 2>&1; then fail 'unknown variable accepted'; fi
grep -q 'bad.sole:2' "$temporary/compile.log" || fail 'source location missing'
printf 'def main() -> int32:\n    return 7\n' > "$temporary/exit.sole"
status=0
"$compiler" run "$temporary/exit.sole" > "$temporary/compile.log" 2>&1 || status=$?
[ "$status" -eq 7 ] || fail 'run exit status'
for emit in llvm object; do
    if "$compiler" run "$temporary/exit.sole" --emit "$emit" -o "$temporary/not-run.$emit" > "$temporary/compile.log" 2>&1; then
        fail "run accepted $emit emission"
    fi
    grep -q 'run requires binary emission' "$temporary/compile.log" || fail 'run emission diagnostic'
    test ! -e "$temporary/not-run.$emit" || fail 'run emitted an unused artifact'
done

cc -Wall -Wextra -Werror -fsyntax-only "$root/lib/runtime/system.c"

mkdir -p "$temporary/tools"
for tool in cc as ld; do ln -s "$(command -v "$tool")" "$temporary/tools/$tool"; done
PATH="$temporary/tools" "$compiler" build "$hello" -o "$temporary/hello" > "$temporary/compile.log" 2>&1 || fail 'build without interpreters'
"$temporary/hello" > "$temporary/actual"
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
mv "$temporary/installed" "$temporary/relocated"
unset SOLE_HOME SOLE_LIB
cd "$temporary"
PATH="$temporary/tools" "$temporary/relocated/bin/sole" build "$imports" -o "$temporary/imports" > "$temporary/compile.log" 2>&1 || fail 'relocated installation'
"$temporary/imports" > "$temporary/actual"
printf '6\ntrue\nhahaha\n97\n' > "$temporary/expected"
cmp -s "$temporary/expected" "$temporary/actual" || fail 'relocated library'
cd "$root"
echo "Passed $count fixture cases, CLI checks, and interpreter-free relocation."
