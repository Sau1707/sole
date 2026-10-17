#!/bin/sh
set -eu

tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for suite in harness syntax imports types c-api raw stdlib-reuse bytes constructors classes loops sumtypes features run cli backend-errors output-safety atomic-write files-helpers process format install; do
    sh "$tests/$suite.sh"
done
