# Compiler tests

Run from the repository root with a built `sole` on `PATH`, or select a compiler
with `SOLE_COMPILER=/absolute/path/to/sole`:

```sh
sh compiler/tests/suite.sh
```

CI uses `suite.sh`, which runs these independently usable runners in order:

| Command | Coverage |
| --- | --- |
| `sh compiler/tests/harness.sh` | Runner behavior with controlled compiler substitutes |
| `sh compiler/tests/syntax.sh` | Grammar validation and syntax regressions |
| `sh compiler/tests/types.sh` | Compiler type-system unit tests |
| `sh compiler/tests/bytes.sh` | Byte-literal execution, validation, syntax, and formatting |
| `sh compiler/tests/run.sh` | Build/check and execution fixtures in `cases/` |
| `sh compiler/tests/cli.sh` | CLI, emission, interpreter-free execution, and relocation |
| `sh compiler/tests/backend-errors.sh` | Backend failure reporting |
| `sh compiler/tests/output-safety.sh` | Output-path safety |
| `sh compiler/tests/atomic-write.sh` | Atomic output writes |
| `sh compiler/tests/format.sh` | Formatter behavior and `format-cases/` fixtures |
| `sh compiler/tests/install.sh` | Release installer integration |

`syntax.sh` also accepts source paths to validate instead of running its suite.
Runners use isolated temporary directories and honor `TMPDIR`, defaulting to
`/tmp/opencode` when available. The integration checks need the system C compiler
and standard Unix tools. `SOLE_TEST_RELEASE` can select a release archive for the
installer tests.

## Execution fixture schema

Each directory under `cases/` is one fixture. Names are descriptive identifiers;
numeric prefixes need not be contiguous. Keep existing paths stable when possible.

| Path | Meaning |
| --- | --- |
| `source/` | Source tree copied into an isolated workspace, preserving symlinks |
| `mode` | Required: `run`, `trap`, `exit`, `reject-build`, or `reject-check` |
| `entry` | Optional source-relative entry path; defaults to `main.sole` |
| `optimize` | Optional whitespace-separated `-O0`, `-O1`, `-O2`, or `-O3` values; defaults to `-O2` |
| `expected` | Required exact stdout bytes for `run` and `exit`, including final newlines |
| `status` | Required expected process exit status for `exit` |
| `diagnostic` | Optional fixed-string diagnostic patterns for rejection modes |
| `library-override` | Optional marker selecting this fixture's `library/` instead of the repository library |
| `library/` | Library tree used when `library-override` is present |
| `module-env` | Optional value for `SOLE_MODULE_TEST` |

`run` requires a successful build and execution. `exit` checks the specified exit
status and stdout. `trap` requires an illegal-instruction or trap signal.
`reject-build` and `reject-check` require the respective compiler command to exit
with status 1 and emit a `sole: error: ` source diagnostic; crashes do not count as
valid rejections. When `diagnostic` is present, at least one of its patterns must
occur in the compiler output.

Before compilation, `@CASE_ROOT@` in copied `.sole` files is replaced with the
absolute copied source directory, and `@DATA_ROOT@` with an isolated data directory
containing `0/` and `1/` subdirectories.

`run.sh` requires `timeout` and bounds each compiler invocation to 60 seconds and
each program invocation to 10 seconds. Override these with
`SOLE_TEST_COMPILE_TIMEOUT` and `SOLE_TEST_RUN_TIMEOUT` (positive integer seconds).
Timeouts fail the fixture, including rejection and trap cases.

Every optimization listed in `optimize` runs the complete fixture independently.
Use one value per line when covering multiple levels:

```text
-O0
-O2
```

Omit metadata that merely restates a default. Consolidate optimization variants
only when all other paths, file bytes, and symlink targets are identical, preserving
every optimization run in the retained fixture. Do not merge merely similar
programs or cases with different expectations, modes, or diagnostic patterns.
