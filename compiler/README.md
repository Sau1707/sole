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
primitives/              Backend-independent primitive descriptors and intrinsic names
raw/                     Direct LLVM C API and C/system foreign interfaces
codegen/llvm/            Direct token-to-LLVM compilation and native emission
  context.sole           Mutable compilation state and LLVM-valued expressions
  scalars.sole           LLVM scalar representations and instruction selection
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

Semantic type queries consult `primitives/` without depending on LLVM type names
or instruction selection. These are compiler descriptors, not library-defined
scalar types. This extraction does not introduce new compilation phases or make
scalars library-defined. Symbol and validation helpers still accept
the shared compilation context, and diagnostic adapters still understand that
context. Token positions, file names, and line numbers remain the existing source
location representation. There is no compiler-owned AST, HIR, MIR, optimization
pass manager, incremental cache, or shared target-description layer yet.

Add those subsystems only when their contracts and implementations are needed.
Do not use `support/` as a home for otherwise unowned compiler responsibilities.

`raw/llvm.sole` exposes LLVM's raw type and instruction-building API, plus native
verification and emission. `raw/c.sole` exposes compiler-facing C/system calls.
Its bindings contain no Sole runtime functions. These native interfaces are
separate from the Sole type descriptors in `primitives/`. LLVM handles use `ptr`,
32-bit C counts/enums use `uint32`/`int32`, and `size_t` uses `uint64` on the
current Linux x86-64 target. Raw calls require valid handles, native array
storage, and the matching LLVM resource-disposal calls.

## Runtime boundary

Resource lookup, filesystem safety, atomic writes, process spawning/waiting,
and float-bit reinterpretation are implemented in `lib/runtime/system.sole`.
`lib/runtime/linux.sole` isolates the current glibc/Linux ABI, including native
`stat` layout, thread-local errno, and environment lookup. File intrinsic bodies
are implemented in `lib/runtime/io.sole`, loaded as a compiler-owned module with
the reserved `__sole_mruntime__` prefix independently of library overrides.
Runtime source files are tracked as compilation inputs like other modules.

`lib/runtime/native.ll` retains the irreducible startup argument storage/access
and entry-point initialization, plus the existing low-level allocation and print
operations. Applications no longer compile or link a Sole-specific C runtime.
The old C `sole_rt_*` symbols are removed; `wrappers.system` preserves existing
library imports as ordinary Sole functions, not foreign C declarations.

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

Older released seed compilers still require their original C runtime when
producing stage 1. Bootstrap copies those seed resources from
`<seed-prefix>/share/sole` into its temporary seed home; stage 2 and stage 3 use
only the current Sole/LLVM runtime. Set `SOLE_BOOTSTRAP_HOME` when an older seed's
resource directory is installed elsewhere.
