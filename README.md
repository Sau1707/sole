# Sole

Sole is a statically typed, indentation-based language with an LLVM backend. It compiles to **native executables**. The compiler is written in Sole, organized into [feature-specific modules](compiler/README.md) starting at [`compiler/main.sole`](compiler/main.sole).

**Sole 0.0.0 is self-hosting and Python-free.** A native Sole compiler builds its own source again, producing a byte-for-byte identical compiler. Builds, tests, and installation require no Python interpreter or packages. This is still an experimental language, not a production-ready ecosystem.

```sole
import core

struct Point:
    x: float64
    y: float64

class Counter:
    value: int32

    def add(self, amount: int32) -> void:
        self.value = self.value + amount

def main() -> int32:
    origin: Point = Point(0.0, 0.0)
    counter: Counter = Counter(0)
    counter.add(42)
    core.print(counter.value)
    return 0
```

## Install the released compiler

Requires Linux x86-64, glibc, LLVM 21 (`libLLVM.so.21.1`), a native C toolchain,
`curl`, `tar`, and `sha256sum`. Install your distribution's `llvm-21-dev` and
build tools first. Then:

```sh
curl -fsSL https://raw.githubusercontent.com/Sau1707/sole/main/install-release.sh -o install-sole.sh
sh install-sole.sh
export PATH="$HOME/.local/bin:$PATH"
sole --version
```

The installer downloads release **0.0.0**, verifies its SHA-256 checksum, and
installs the compiler, runtime, and standard library under `~/.local`. Add the
`export PATH` line to your shell configuration to keep it across sessions.
Use `sh install-sole.sh /absolute/prefix` for another location, or set
`SOLE_VERSION` to select a published version. No source build is needed.

From a checkout, `make up` installs this same released compiler and the VS Code
extension. Override the destination with `make up PREFIX=/absolute/prefix`.
`make down` removes only the editor extension, leaving the compiler installed.

## Bootstrap from source

Prebuilt Linux x86-64 archives are available on the
[GitHub releases page](https://github.com/Sau1707/sole/releases). They require
LLVM 21 and a native C toolchain. Verify the archive against `SHA256SUMS`, extract
it, and copy its `bin/` and `share/` directories into your installation prefix
(for example `~/.local`).

The bundled native seed requires Linux x86-64, glibc, and `libLLVM.so.21.1` with
its dependencies. Install your distribution's LLVM 21 development package (for
example `llvm-21-dev`) and native C toolchain (`cc`, assembler, and linker).
POSIX shell utilities, `make`, and `sha256sum` handle builds and tests. No LLVM
headers, Clang executable, or interpreter is needed by Sole itself.

```sh
./bootstrap.sh
export PATH="$PWD/.build:$PATH"
```

`bootstrap.sh` uses an existing `.build/sole` or the checksummed native seed in
`bootstrap/sole`. It builds stages 1, 2, and 3, compares stages 2 and 3, installs
`.build/sole`, and records binary and source hashes in `.build/bootstrap-proof.txt`.
`./bootstrap.sh --seed` explicitly starts over with the bundled seed. A native
seed is a trusted input; this is not a source-only bootstrap. See
[bootstrap details](bootstrap/README.md).

Set `SOLE_LLVM_LIB` to the shared library's linker name if auto-detection fails,
e.g. `SOLE_LLVM_LIB=LLVM-21 ./bootstrap.sh`. Set `SOLE_BOOTSTRAP` to the absolute
path of another compatible native Sole compiler. A linker override does not
change the bundled seed's LLVM shared-library ABI requirement.

Set `SOLE_CC` to override the C linker driver. Native execution has been tested on Linux x86-64.

### Install

```sh
make install                         # defaults to $HOME/.local
make install PREFIX=/absolute/prefix
```

Installation places `sole` in `bin/` and its runtime and standard library in
`share/sole/`. This tree can be moved without rebuilding or setting environment
variables. `DESTDIR` is supported for staged packaging. The installed compiler
still requires compatible LLVM shared libraries and the native toolchain.

## Compile and run

```sh
cat > hello.sole <<'EOF'
import core


def main() -> int32:
    core.print("Hello from Sole!")
    return 0
EOF
sole check hello.sole
sole run hello.sole

mkdir -p .build
sole build hello.sole -o .build/hello
./.build/hello
```

Emit LLVM IR or a relocatable object instead of linking:

```sh
sole build hello.sole --emit llvm -o .build/hello.ll
sole build hello.sole --emit object -o .build/hello.o
```

Use `-O0`, `-O1`, `-O2` (default), or `-O3`. `--link NAME` links a native library, e.g. `--link LLVM-21` when compiling the compiler itself.

The compiler finds `runtime/` and `lib/` relative to its executable, both in a
checkout and an installed tree. Set `SOLE_HOME` to a directory containing
`runtime/` and `lib/`, or `SOLE_LIB` to override just the library. Ordinary
compiled programs need neither the compiler resources nor LLVM unless they
explicitly link LLVM themselves. See [SOL014 — Compilation](docs/SOL014.md).

## Imports and standard library

Use one module per file and qualified names:

```sole
import core

import math
import strings

def main() -> void:
    core.print(math.gcd(48, 18))
    core.print(strings.contains("Hello, Sole!", "Sole"))
```

`import geometry` loads `geometry.sole` beside the importing file. `import geometry.points` loads `geometry/points.sole` and exposes names such as `geometry.points.Point`. Use `import geometry.points as points` for shorter names such as `points.Point`. Functions, structs, classes, and extern declarations are available through the imported namespace; types work in annotations and constructors. Modules do not implicitly re-export their imports. There are no wildcard imports or `from` syntax.

Modules are loaded once by canonical file path. Cycles, duplicate imports in one file, and rebinding module namespaces are errors. Only the entry file's `main` is the program entry point.

Every library operation requires an explicit import, including `core.len`,
`core.slice`, and `core.print`, declared in `lib/core.sole`. There are no implicit
functions. Type casts such as `int64(value)` remain language syntax.

If no module exists beside the importing file, Sole searches the entry file's directory, then `lib/`, `lib/pure/`, `lib/impure/`, and `lib/wrappers/`. This lets nested modules import sibling project folders. Set `SOLE_LIB` to override the library root. See [SOL020](docs/SOL020.md) and the [standard-library overview](docs/SOL021.md).

| Directory | Contents |
| --- | --- |
| `lib/core.sole` | Explicitly imported core operations, including `len`, `slice`, `print`, arrays, pointers, and native I/O |
| `lib/pure/` | Sole-only modules: `math`, `strings`, `ascii`, `bisect`, `statistics`, `os.path` |
| `lib/impure/` | Sole APIs backed by native services: `files`, `env` |
| `lib/wrappers/` | Unsafe C declarations: `libc`, `cmath` |

Use `import wrappers.cmath` for explicit category access, e.g. `wrappers.cmath.sqrt(16.0)`. Foreign libraries still require `--link NAME` when not linked by default.

## VS Code syntax highlighting

The [Sole VS Code extension](.editors/vscode/README.md) adds syntax coloring for
`.sole` files, comment toggling, bracket matching, and indentation support. Run
`make up` to install the released compiler and build and install the extension,
or `make down` to uninstall the extension and remove local extension build
dependencies. Requires Node.js 22+, npm, Make, the VS Code `code` CLI, and the
release-installation prerequisites above. See its README for details and preview
instructions.

## Language principles

- **One canonical construct per task:** `def` for functions, annotated declarations, `=` for assignment, `while` for iteration, and explicit type-name casts.
- **Explicit types:** `int8`, `int16`, `int32`, `int64`, their unsigned equivalents, `float32`, `float64`, `bool`, and `str`. No ambiguous `int` type or implicit conversions between typed numeric values.
- **Structs are values; classes are references.** Struct assignment copies fields. Class assignment aliases the same object. Classes support ordinary statically resolved methods; there is no inheritance or hidden metaprogramming.
- **Predictable syntax:** indentation, `#` comments, and Python-style `"""docstrings"""`, not braces or semicolons. No comprehensions, decorators, generators, lambdas, operator overloading, chained comparisons, augmented assignment, or implicit truthiness.
- **Compiled execution:** the Sole-written lexer, parser, and type checker emit LLVM IR. LLVM's C API verifies, optimizes, and emits native objects. C is used only for a small POSIX system runtime, not the language frontend.

Also implemented: recursion, forward declarations, `if`/`elif`/`else`, `break`, `continue`, fixed-size and growable arrays, short-circuit logic, bitwise operations, string construction/comparison/indexing, `join`, `slice`, file I/O, command-line arguments, raw pointers, and scalar C FFI. These additions let Sole implement its own compiler without Python services.

Read the short [Sole specifications](docs/README.md) for syntax, types, and behavior.

## Current limits

- Modules compile together as one program; separate object compilation, generics, interfaces, exceptions, networking APIs, and a package ecosystem are not implemented yet.
- Strings are immutable byte views, conventionally UTF-8. Indexing and slicing operate on bytes, not Unicode characters. The self-hosted lexer accepts ASCII identifiers, ordinary and triple-quoted strings, and basic escapes; raw strings and Unicode escape syntax are not implemented.
- Class objects, growable arrays, and allocated string buffers have **program/instance lifetime**. There is no garbage collector or deallocation, so long-running allocation-heavy programs consume increasing memory.
- Fields are public and constructors initialize all fields positionally in declaration order. There are no user-defined constructors, default fields, nullable references, destructors, or inheritance.
- Fixed arrays and structs copy by value; growable arrays share a mutable reference. Large values can consume significant stack space. Stack exhaustion is not checked.
- File/argument access and `exit` are native system operations. Raw pointers and `extern` are unsafe: incorrect ABI declarations or invalid pointers can corrupt memory.
- Runtime failures trap rather than produce source-level stack traces. Floating-point printing uses libc.

## Lint

Run `make format` to automatically fix that spacing in `compiler/` and `lib/`.
The formatter is built into the compiler and runs without Python:

```sh
sole format file.sole another.sole
sole format --check file.sole
```

`--check` reports files that need formatting without modifying them, exiting 1
if any file would change or an error occurs.

## Test

```sh
make test
```

[`sole.ebnf`](sole.ebnf) defines the token-level syntax. `make test-syntax`
checks sources against that grammar using a native Sole runner; `make test`
includes these checks. See [syntax tests](compiler/tests/README.md#syntax-grammar).

The shell suite runs 179 native fixture cases plus CLI, runtime, bootstrap, and
relocation checks. It covers namespace isolation, aliases, relative/diamond
imports, records and methods, foreign wrappers, type errors, traps, and library
behavior. Relocation tests compile with only `cc`, `as`, and `ld` on `PATH`.
See [tests](compiler/tests/README.md).

The native formatter is covered by 18 migrated spacing and preservation cases.

## Layout

| Path | Purpose |
| --- | --- |
| `compiler/main.sole` | Compiler entry point |
| `compiler/pipeline.sole` | Compilation pipeline coordinator |
| `compiler/frontend/` | Lexing, imports, declarations, parsing, symbols, and validation |
| `compiler/backend/` | LLVM types, values, operators, functions, and target emission |
| `compiler/driver/` | CLI and linker handling |
| `compiler/platform/` | Native system bindings |
| `lib/pure/`, `lib/impure/`, `lib/wrappers/` | Standard-library modules |
| `bootstrap/sole` | Checksummed native bootstrap seed |
| `bootstrap.sh` | Native rebuilds and fixed-point verification |
| `install.sh` | Relocatable native installation |
| `runtime/*.ll` | Shared allocation, arrays, strings, and native output helpers |
| `runtime/system.c` | Small POSIX file/argument runtime |
| `compiler/tests/` | Compiler and native execution tests |
