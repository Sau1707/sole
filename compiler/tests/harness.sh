#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-harness-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
SOLE_TEST_COMPILE_TIMEOUT=1
SOLE_TEST_RUN_TIMEOUT=1
export SOLE_TEST_COMPILE_TIMEOUT SOLE_TEST_RUN_TIMEOUT

tests="$temporary/checkout/compiler/tests"
fixture="$tests/cases/rejection"
mkdir -p "$fixture/source"
cp "$root/compiler/tests/run.sh" "$root/compiler/tests/temp-root.sh" "$tests/"
printf 'invalid\n' > "$fixture/source/main.sole"
cat > "$temporary/compiler" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$SOLE_HARNESS_CALLS"
[ -f "$2" ] || exit 127
printf '%s\n' "${SOLE_HARNESS_DIAGNOSTIC:-sole: error: regression input}"
case "$SOLE_HARNESS_STATUS" in
    hang|ignore-term)
        if [ "$SOLE_HARNESS_STATUS" = ignore-term ]; then trap '' TERM; fi
        while :; do sleep 1; done
        ;;
esac
if [ "$SOLE_HARNESS_STATUS" = signal ]; then
    kill -SEGV "$$"
fi
exit "$SOLE_HARNESS_STATUS"
EOF
chmod +x "$temporary/compiler"
SOLE_HARNESS_CALLS="$temporary/calls"
export SOLE_HARNESS_CALLS

expect_failure() {
    printf '%s\n' "$1" > "$fixture/mode"
    if SOLE_COMPILER="$temporary/compiler" SOLE_HARNESS_STATUS="$2" \
        sh "$tests/run.sh" > "$temporary/log" 2>&1; then
        echo "FAIL: harness accepted mode $1 with status $2" >&2
        exit 1
    fi
    if ! grep -Fq "$3" "$temporary/log"; then
        cat "$temporary/log" >&2
        echo "FAIL: unexpected harness failure for mode $1 with status $2" >&2
        exit 1
    fi
}

for mode in rnu reject-typo typo-check; do
    expect_failure "$mode" 1 "unknown fixture mode: $mode"
done
for mode in reject-build reject-check; do
    for status in 2 126 127 139 signal; do
        expect_failure "$mode" "$status" 'compiler exited with status'
    done
    for status in 124 137; do
        expect_failure "$mode" "$status" "compiler exited with status $status, expected 1"
        if grep -Fq 'timed out' "$temporary/log"; then
            echo "FAIL: completed compiler status $status was treated as a timeout" >&2
            exit 1
        fi
    done
    expect_failure "$mode" 0 'was accepted'
    for status in hang ignore-term; do
        expect_failure "$mode" "$status" 'compiler timed out after 1 seconds'
    done
    SOLE_HARNESS_DIAGNOSTIC='internal error' expect_failure "$mode" 1 'has no source diagnostic'
    printf '%s\n' "$mode" > "$fixture/mode"
    SOLE_COMPILER="$temporary/compiler" SOLE_HARNESS_STATUS=1 \
        sh "$tests/run.sh" > "$temporary/log" 2>&1
    grep -Fq 'Passed 1 fixture runs.' "$temporary/log"
    grep -Fq 'main.sole -O2 -o ' "$SOLE_HARNESS_CALLS"
done

for setting in SOLE_TEST_COMPILE_TIMEOUT SOLE_TEST_RUN_TIMEOUT; do
    for value in '' 0 00 -1 1.5 1s invalid; do
        if env "$setting=$value" SOLE_COMPILER="$temporary/compiler" SOLE_HARNESS_STATUS=1 \
            sh "$tests/run.sh" > "$temporary/log" 2>&1; then
            echo "FAIL: harness accepted $setting=$value" >&2
            exit 1
        fi
        grep -Fq "$setting must be a positive integer number of seconds" "$temporary/log"
    done
done

printf '%s\n' -O0 -O2 > "$fixture/optimize"
: > "$SOLE_HARNESS_CALLS"
SOLE_COMPILER="$temporary/compiler" SOLE_HARNESS_STATUS=1 \
    sh "$tests/run.sh" > "$temporary/log" 2>&1
grep -Fq 'Passed 2 fixture runs.' "$temporary/log"
test "$(wc -l < "$SOLE_HARNESS_CALLS")" -eq 2
grep -Fq 'main.sole -O0 -o ' "$SOLE_HARNESS_CALLS"
grep -Fq 'main.sole -O2 -o ' "$SOLE_HARNESS_CALLS"
printf '%s\n' -O9 > "$fixture/optimize"
expect_failure reject-check 1 'unknown optimization: -O9'
: > "$fixture/optimize"
expect_failure reject-check 1 'empty optimization list'
printf ' \t\n' > "$fixture/optimize"
expect_failure reject-check 1 'empty optimization list'
printf '*\n' > "$fixture/optimize"
expect_failure reject-check 1 'unknown optimization: *'
rm "$fixture/optimize"
printf 'custom entry.sole\n' > "$fixture/entry"
mv "$fixture/source/main.sole" "$fixture/source/custom entry.sole"
printf '%s\n' -O0 > "$fixture/optimize"
: > "$SOLE_HARNESS_CALLS"
SOLE_COMPILER="$temporary/compiler" SOLE_HARNESS_STATUS=1 \
    sh "$tests/run.sh" > "$temporary/log" 2>&1
grep -Fq 'Passed 1 fixture runs.' "$temporary/log"
grep -Fq 'custom entry.sole -O0 -o ' "$SOLE_HARNESS_CALLS"
mv "$fixture/source/custom entry.sole" "$fixture/source/main.sole"
rm "$fixture/entry" "$fixture/optimize"

cat > "$temporary/runtime-compiler" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        shift
        cat > "$1" <<'PROGRAM'
#!/bin/sh
if [ "${SOLE_HARNESS_EXPECTED_MODULE+x}" = x ]; then
    printf 'runtime invocation\n' >> "$SOLE_HARNESS_CALLS"
    if [ "${SOLE_MODULE_TEST:-}" != "$SOLE_HARNESS_EXPECTED_MODULE" ]; then
        printf 'unexpected runtime module environment\n' >&2
        exit 99
    fi
fi
printf 'actual output\n'
printf 'runtime stderr marker\n' >&2
case "${SOLE_HARNESS_RUNTIME_STATUS:-0}" in
    signal) kill -ILL "$$" ;;
    hang|ignore-term)
        if [ "$SOLE_HARNESS_RUNTIME_STATUS" = ignore-term ]; then trap '' TERM; fi
        while :; do sleep 1; done
        ;;
esac
exit "${SOLE_HARNESS_RUNTIME_STATUS:-0}"
PROGRAM
        chmod +x "$1"
        exit 0
    fi
    shift
done
exit 1
EOF
chmod +x "$temporary/runtime-compiler"
for mode in run trap exit; do
    printf '%s\n' "$mode" > "$fixture/mode"
    printf '124\n' > "$fixture/status"
    for status in hang ignore-term; do
        if SOLE_COMPILER="$temporary/runtime-compiler" SOLE_HARNESS_RUNTIME_STATUS="$status" \
            sh "$tests/run.sh" > "$temporary/log" 2>&1; then
            echo "FAIL: harness accepted $mode program that $status" >&2
            exit 1
        fi
        grep -Fq 'program timed out after 1 seconds' "$temporary/log"
        grep -Fq 'runtime stderr marker' "$temporary/log"
    done
done
printf 'exit\n' > "$fixture/mode"
printf 'actual output\n' > "$fixture/expected"
for status in 124 137; do
    printf '%s\n' "$status" > "$fixture/status"
    if ! SOLE_COMPILER="$temporary/runtime-compiler" SOLE_HARNESS_RUNTIME_STATUS="$status" \
        sh "$tests/run.sh" > "$temporary/log" 2>&1; then
        cat "$temporary/log" >&2
        echo "FAIL: harness rejected completed program status $status" >&2
        exit 1
    fi
    grep -Fq 'Passed 1 fixture runs.' "$temporary/log"
done
printf 'expected output\n' > "$fixture/expected"
for mode in run exit; do
    printf '%s\n' "$mode" > "$fixture/mode"
    printf '7\n' > "$fixture/status"
    if SOLE_COMPILER="$temporary/runtime-compiler" SOLE_HARNESS_RUNTIME_STATUS=9 \
        sh "$tests/run.sh" > "$temporary/log" 2>&1; then
        echo 'FAIL: harness accepted wrong runtime status' >&2
        exit 1
    fi
    expected_status=0
    if [ "$mode" = exit ]; then expected_status=7; fi
    grep -Fq "program exited with status 9, expected $expected_status" "$temporary/log"
    grep -Fq 'runtime stderr marker' "$temporary/log"
    if SOLE_COMPILER="$temporary/runtime-compiler" SOLE_HARNESS_RUNTIME_STATUS="$expected_status" \
        sh "$tests/run.sh" > "$temporary/log" 2>&1; then
        echo 'FAIL: harness accepted wrong runtime output' >&2
        exit 1
    fi
    grep -Fq -- '-expected output' "$temporary/log"
    grep -Fq '+actual output' "$temporary/log"
    grep -Fq 'runtime stderr marker' "$temporary/log"
done

printf 'fixture value\n' > "$fixture/module-env"
printf 'actual output\n' > "$fixture/expected"
for mode in run exit trap; do
    printf '%s\n' "$mode" > "$fixture/mode"
    printf '0\n' > "$fixture/status"
    runtime_status=0
    expected_module='parent value'
    if [ "$mode" = run ]; then expected_module='fixture value'; fi
    if [ "$mode" = trap ]; then runtime_status=signal; fi
    : > "$SOLE_HARNESS_CALLS"
    if ! SOLE_MODULE_TEST='parent value' SOLE_HARNESS_EXPECTED_MODULE="$expected_module" \
        SOLE_COMPILER="$temporary/runtime-compiler" SOLE_HARNESS_RUNTIME_STATUS="$runtime_status" \
        sh "$tests/run.sh" > "$temporary/log" 2>&1; then
        cat "$temporary/log" >&2
        echo "FAIL: $mode runtime environment or signal handling changed" >&2
        exit 1
    fi
    test "$(wc -l < "$SOLE_HARNESS_CALLS")" -eq 1
    grep -Fq 'Passed 1 fixture runs.' "$temporary/log"
done
for status in 0 1 139; do
    if SOLE_COMPILER="$temporary/runtime-compiler" SOLE_HARNESS_RUNTIME_STATUS="$status" \
        sh "$tests/run.sh" > "$temporary/log" 2>&1; then
        echo "FAIL: harness accepted trap mode with status $status" >&2
        exit 1
    fi
    grep -Fq 'expected a trap signal' "$temporary/log"
done
rm "$fixture/module-env"

cat > "$temporary/library-compiler" <<'EOF'
#!/bin/sh
set -eu
if [ "${SOLE_LIB:-}" != "$SOLE_EXPECTED_LIB" ]; then
    echo 'FAIL: unit test inherited the library override' >&2
    exit 1
fi
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        shift
        printf '#!/bin/sh\nexit 0\n' > "$1"
        chmod +x "$1"
        exit 0
    fi
    shift
done
exit 1
EOF
chmod +x "$temporary/library-compiler"
SOLE_LIB=/no/such/library SOLE_EXPECTED_LIB="$root/lib" SOLE_COMPILER="$temporary/library-compiler" \
    sh "$root/compiler/tests/types.sh"
echo 'Passed fixture harness and unit-test library isolation checks.'
