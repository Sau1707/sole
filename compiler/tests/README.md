# Native tests

Run `make test`. The shell harness builds and executes the native Sole compiler;
no interpreter or third-party test framework is needed.

`cases/` preserves the former compiler, module, and library regression fixtures.
Each case contains Sole sources, an entry filename, an optimization level, and a
mode: `check`, `build`, `run`, `exit`, `trap`, `reject-check`, or `reject-build`. Successful
execution is compared byte-for-byte with `expected`, including embedded NULs.
`@CASE_ROOT@` and `@DATA_ROOT@` are replaced with isolated temporary paths.
`exit` fixtures compare the process status with their `status` file.

`format-cases/` preserves 18 spacing, docstring, comment, CRLF, invalid-input,
and idempotence cases for the native formatter. `compiler/tests/format.sh` runs them.

The harness also covers CLI errors, output protection, IR/object emission,
runtime C warnings, bootstrap hashes, and an installation moved to a
different prefix and run with only native toolchain executables on `PATH`.

`types.sh` builds `types.sole` against the compiler's type classes. It checks
native representations, signedness, arithmetic and comparison instructions,
casts, invalid operations, and integer bounds for every built-in type.

Set `SOLE_COMPILER` to test another native compiler. Temporary directories honor
`TMPDIR` and are removed on exit. Rejection and trap fixtures must fail; rejection
fixtures must also emit an error diagnostic.

## Syntax grammar

`make test-syntax` builds `syntax.sole` with the native compiler and reads
[`sole.ebnf`](../sole.ebnf) to validate compiler, library, example (when present),
and successful fixture sources. `make test` runs this before the compiler suite.
To check specific files, run `sh compiler/tests/syntax.sh path/to/file.sole ...`.

The runner reuses the compiler lexer, including indentation, comments, string
escapes, and implicit line continuation. Uppercase grammar symbols are lexer
token categories; quoted terminals match syntax, never string/number contents.
Identifiers exclude the compiler's reserved keywords. Numeric token validity
and type rules remain the compiler's responsibility.

The EBNF subset uses `=` and `;` for rules, `,` for sequences, `|` for choices,
parentheses for grouping, `[]` for optional terms, `{}` for repetition, and `#`
comments. Rules may refer forward. Alternatives are tried in order and
repetitions are greedy, so keep the grammar predictive and non-left-recursive.
The suite includes malformed syntax, undefined rules, and an alternate grammar
to verify that acceptance really depends on the file.

This is a syntax contract, not a second type checker: undefined names, invalid
assignment targets, non-call expression statements, return types, and loop
context are still checked by the compiler. The compiler's existing lowering
parser is unchanged; parser generation is not part of these tests.
