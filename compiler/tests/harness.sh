#!/bin/sh
set -eu
ulimit -c 0

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/compiler/tests/temp-root.sh"
temporary=$(mktemp -d "$temp_root/sole-harness-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

tests="$temporary/checkout/compiler/tests"
fixture="$tests/cases/rejection"
mkdir -p "$fixture/source"
cp "$root/compiler/tests/run.sh" "$root/compiler/tests/temp-root.sh" "$tests/"
printf 'main.sole\n' > "$fixture/entry"
printf '%s\n' -O2 > "$fixture/optimize"
printf 'invalid\n' > "$fixture/source/main.sole"
cat > "$temporary/compiler" <<'EOF'
#!/bin/sh
if [ "$1" = --version ]; then
    echo 'reached CLI checks'
    exit 0
fi
printf '%s\n' "${SOLE_HARNESS_DIAGNOSTIC:-sole: error: regression input}"
if [ "$SOLE_HARNESS_STATUS" = signal ]; then
    kill -SEGV "$$"
fi
exit "$SOLE_HARNESS_STATUS"
EOF
chmod +x "$temporary/compiler"

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
    expect_failure "$mode" 0 'was accepted'
    SOLE_HARNESS_DIAGNOSTIC='internal error' expect_failure "$mode" 1 'has no source diagnostic'
    # A valid rejection must reach the CLI checks.
    expect_failure "$mode" 1 'FAIL: version'
done

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
