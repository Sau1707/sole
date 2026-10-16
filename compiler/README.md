# Compiler structure

`main.sole` is the compiler entry point. Keep it here: Sole resolves compiler
imports relative to the entry file's directory.

```text
driver/                  CLI commands, compilation orchestration, native linking
diagnostics/             Error reporting and source-location rendering
syntax/
  lexer/                 Token storage, scanning, character classification
  parser/                Token consumption, precedence, EBNF recognition
  formatter.sole         Source formatting
semantic/
  model.sole             Declaration metadata
  resolve/               Declaration scanning, symbol lookup, intrinsic names
  types/                 Language type queries
  check/                 Declaration and recursive value-layout validation
modules/                 Import loading, dependency tracking, name qualification
codegen/llvm/            Direct token-to-LLVM compilation and native emission
  context.sole           Mutable compilation state and LLVM-valued expressions
  scalars/               Primitive descriptors and LLVM instruction selection
tests/                   Unit, integration, executable, and rejection tests
```

## Current compilation flow

`driver.pipeline` loads and qualifies imported token streams, scans declarations,
validates them, then asks the LLVM backend to compile function bodies. Expression
and statement compilation still consumes tokens while performing semantic checks
and emitting textual LLVM IR. These implementations live in `codegen/llvm/`, not
in a purported AST parser or target-independent lowering phase.

The EBNF recognizer in `syntax/parser/grammar.sole` is a separate syntax-checking
tool. Its grammar asset is `syntax/parser/sole.ebnf`; it is not the compilation
parser and does not construct an AST.

This organization does not introduce new phase boundaries. Semantic queries still
consult primitive LLVM descriptors, symbol and validation helpers still accept
the shared compilation context, and diagnostic adapters still understand that
context. Token positions, file names, and line numbers remain the existing source
location representation. There is no compiler-owned AST, HIR, MIR, optimization
pass manager, incremental cache, or shared target-description layer yet.

Add those subsystems only when their contracts and implementations are needed.
Do not use `support/` as a home for otherwise unowned compiler responsibilities.

## Verification

Install a released Sole compiler first (see the root README), then run from the
repository root. Bootstrap uses `sole` on `PATH`, or the compiler specified by
`SOLE_BOOTSTRAP`:

```sh
sh scripts/bootstrap-ci.sh
sha256sum -c .build/bootstrap-proof.txt
SOLE_COMPILER="$PWD/.build/sole" sh compiler/tests/suite.sh
npm --prefix .editors/vscode test
```

Bootstrap checks that stage 2 and stage 3 are byte-for-byte identical. Packaging
and installer tests must use the same `compiler/syntax/parser/sole.ebnf` asset
path as the syntax command.
