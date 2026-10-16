#!/bin/sh
set -eu

tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for suite in harness syntax types bytes constructors loops sumtypes features run cli backend-errors output-safety atomic-write format install; do
    sh "$tests/$suite.sh"
done
