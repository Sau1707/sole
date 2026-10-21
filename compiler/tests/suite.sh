#!/bin/sh
set -eu

tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for suite in harness check imports types c-api raw stdlib-reuse bytes constructors structs loops removed-features features run cli backend-errors output-safety atomic-write files-helpers process install; do
    sh "$tests/$suite.sh"
done
