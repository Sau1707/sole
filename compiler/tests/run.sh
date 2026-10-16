#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
timeout_command=$(command -v timeout) || {
    echo 'FAIL: fixture harness requires the timeout command' >&2
    exit 1
}
case "$timeout_command" in
    /*) ;;
    *) timeout_command="$(CDPATH= cd -- "$(dirname -- "$timeout_command")" && pwd)/$(basename "$timeout_command")" ;;
esac
shell_command=$(command -v sh)
case "$shell_command" in
    /*) ;;
    *) shell_command="$(CDPATH= cd -- "$(dirname -- "$shell_command")" && pwd)/$(basename "$shell_command")" ;;
esac
compile_timeout=${SOLE_TEST_COMPILE_TIMEOUT-60}
run_timeout=${SOLE_TEST_RUN_TIMEOUT-10}
for setting in SOLE_TEST_COMPILE_TIMEOUT SOLE_TEST_RUN_TIMEOUT; do
    case "$setting" in
        SOLE_TEST_COMPILE_TIMEOUT) seconds=$compile_timeout ;;
        SOLE_TEST_RUN_TIMEOUT) seconds=$run_timeout ;;
    esac
    case "$seconds" in
        ''|*[!0-9]*) valid=no ;;
        *[1-9]*) valid=yes ;;
        *) valid=no ;;
    esac
    if [ "$valid" = no ]; then
        echo "FAIL: $setting must be a positive integer number of seconds" >&2
        exit 1
    fi
done
compiler=$(command -v "${SOLE_COMPILER:-sole}")
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-tests-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
count=0
log="$temporary/compile.log"
completion="$temporary/completion"

fail() {
    echo "FAIL: $label: $*" >&2
    if [ -f "$log" ]; then cat "$log" >&2; fi
    exit 1
}

bounded() {
    seconds=$1
    shift
    rm -f "$completion"
    "$timeout_command" --kill-after=1s "${seconds}s" "$shell_command" -c '
        marker=$1
        shift
        trap "exit 124" TERM
        "$@"
        status=$?
        printf "%s\n" "$status" > "$marker"
        exit "$status"
    ' sole-test "$completion" "$@"
}

check_deadline() {
    if [ -s "$completion" ]; then
        IFS= read -r status < "$completion"
        return
    fi
    case "$1" in
        124|137) fail "$2 timed out after $3 seconds (status $1)" ;;
    esac
}

compare_output() {
    if ! cmp -s "$case/expected" "$temporary/actual"; then
        diff -u "$case/expected" "$temporary/actual" >&2 || :
        fail 'output differs'
    fi
}

for case in "$root"/compiler/tests/cases/*; do
    set -f
    label=$(basename "$case")
    log="$temporary/compile.log"
    rm -f "$log"
    mode=$(cat "$case/mode")
    case "$mode" in
        run|trap|exit|reject-build|reject-check) ;;
        *) fail "unknown fixture mode: $mode" ;;
    esac
    entry=main.sole
    if [ -f "$case/entry" ]; then entry=$(cat "$case/entry"); fi
    optimizations=-O2
    if [ -f "$case/optimize" ]; then optimizations=$(cat "$case/optimize"); fi
    set -- $optimizations
    [ "$#" -gt 0 ] || fail 'empty optimization list'
    for optimize do
        case "$optimize" in
            -O0|-O1|-O2|-O3) ;;
            *) fail "unknown optimization: $optimize" ;;
        esac
        label="$(basename "$case") [$optimize]"
        log="$temporary/compile.log"
        rm -f "$log"
        work="$temporary/case"
        rm -rf -- "$work"
        mkdir -p "$work/data/0" "$work/data/1"
        cp -R "$case/source" "$work/source"
        find "$work/source" -type f -name '*.sole' | while IFS= read -r source; do
            sed "s|@CASE_ROOT@|$work/source|g; s|@DATA_ROOT@|$work/data|g" "$source" > "$source.tmp"
            mv "$source.tmp" "$source"
        done
        command=build
        case "$mode" in reject-check) command=check ;; esac
        library="$root/lib"
        if [ -f "$case/library-override" ]; then library="$case/library"; fi
        module_env=
        if [ -f "$case/module-env" ]; then module_env=$(cat "$case/module-env"); fi
        status=0
        SOLE_HOME="$root" SOLE_LIB="$library" SOLE_MODULE_TEST="$module_env" \
            bounded "$compile_timeout" \
            "$compiler" "$command" "$work/source/$entry" "$optimize" -o "$work/program" > "$log" 2>&1 || status=$?
        check_deadline "$status" compiler "$compile_timeout"
        if [ "$status" -eq 0 ]; then
            case "$mode" in reject-*) fail 'was accepted' ;; esac
        else
            case "$mode" in
                reject-*)
                    [ "$status" -eq 1 ] || fail "compiler exited with status $status, expected 1"
                    grep -Fq 'sole: error: ' "$log" || fail 'has no source diagnostic'
                    if [ -f "$case/diagnostic" ]; then
                        grep -Fq -f "$case/diagnostic" "$log" || fail 'diagnostic differs'
                    fi
                    ;;
                *) fail "compiler exited with status $status, expected 0" ;;
            esac
        fi
        log="$temporary/run.log"
        case "$mode" in
            run)
                status=0
                SOLE_MODULE_TEST="$module_env" bounded "$run_timeout" \
                    "$work/program" > "$temporary/actual" 2> "$log" || status=$?
                check_deadline "$status" program "$run_timeout"
                [ "$status" -eq 0 ] || fail "program exited with status $status, expected 0"
                compare_output
                ;;
            trap)
                status=0
                bounded "$run_timeout" \
                    "$work/program" > "$temporary/actual" 2> "$log" || status=$?
                check_deadline "$status" program "$run_timeout"
                [ "$status" -gt 128 ] || fail "expected a trap signal, got status $status"
                signal=$(kill -l "$status" 2>/dev/null || :)
                case "$signal" in
                    ILL|SIGILL|TRAP|SIGTRAP) ;;
                    *) fail "expected a trap signal, got status $status" ;;
                esac
                ;;
            exit)
                status=0
                bounded "$run_timeout" \
                    "$work/program" > "$temporary/actual" 2> "$log" || status=$?
                check_deadline "$status" program "$run_timeout"
                expected_status=$(cat "$case/status")
                [ "$status" -eq "$expected_status" ] || fail "program exited with status $status, expected $expected_status"
                compare_output
                ;;
        esac
        count=$((count + 1))
    done
done
echo "Passed $count fixture runs."
