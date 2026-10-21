# Sole

A small, statically typed, indentation-based language with an LLVM backend. It compiles to **native executables** and its compiler is written in Sole.


## Install the released compiler

```sh
curl -fsSL https://github.com/Sau1707/sole/releases/latest/download/install.sh | sh
```


<br />

## Example
```sole
import core


def fibonacci(n: int64) -> int64:
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)


def main() -> int32:
    n: int64 = 40
    result: int64 = fibonacci(n)

    return 0
```



<br />

### Minimal language core

- `int8`–`int64`, `uint8`–`uint64`, `float32`, `float64`, `bool`, `ptr`, and `void`.
- Functions, imports, and typed external C declarations.
- Data-only structs, fixed-size arrays, strings, and dynamic arrays.
- Explicitly typed variables, arithmetic, `if`, `while`, `for … in range(…)`,
  `break`, `continue`, and `return`.

Classes, methods, implicit `self`, enums, tagged unions, pattern matching, and
lambdas are not supported. This is an intentional breaking reduction of the
language, not an alternative class syntax.

Functions and struct constructors take positional arguments only. Constructor
arguments follow field declaration order and are evaluated left to right:
use `Pair(1, 2)`, not `Pair(first=1, second=2)`. Named arguments and augmented
assignments such as `+=` are not supported; write `total = total + value`.
When migrating reordered named calls with side effects, evaluate arguments into
temporaries in their original order before passing them in field order. Parenthesize
a compound right-hand side when expanding `+=`, as in `x = x + (a + b)`.

Structs and fixed arrays have value semantics. Dynamic arrays share storage;
use an explicit array parameter when a function needs to mutate shared data:

```sole
struct Counter:
    value: int32


def increment(counter: Counter[]) -> void:
    counter[0].value = counter[0].value + 1


def main() -> int32:
    counter: Counter[] = [Counter(0)]
    increment(counter)
    return counter[0].value - 1
```

Copying a struct also copies its dynamic-array handles, not the arrays' contents.
The compiler uses single-element arrays for shared counters and parser cursors;
ordinary structs and fixed arrays still copy by value. Raw C pointers remain
unsafe; this reduction does not introduce typed pointers or new ownership rules.

### Ordinary library functions

String helpers are ordinary functions, loaded only when imported:

```sole
import strings
import string_array
```

Use `strings.contains(text, needle)`, `strings.repeat(text, count)`, or
`string_array.index_of(items, value)` instead of methods. `strings` also provides
`starts_with`, `ends_with`, `find`, `replace`, and `partition`.
Matching is byte-based; `find` and `index_of` return `-1` when absent. An empty
needle matches at offset zero. Replacement is non-overlapping and an empty pattern
leaves the text unchanged. Partitioning returns `[before, separator, after]`, or
`[text, "", ""]` for an absent or empty separator. Repetition returns an empty
string for nonpositive counts. Numeric and ASCII convenience methods have been
removed; use explicit arithmetic, ordinary functions, or the typed C API.

### Reading the compiler

Start with `compiler/driver/pipeline.sole`, which coordinates:

1. `compiler/syntax/lexer/`: source text to located tokens.
2. `compiler/modules/loader.sole`: import loading and name qualification.
3. `compiler/semantic/resolve/`: declaration collection and symbol lookup.
4. `compiler/semantic/check/`: declaration and struct-layout validation.
5. `compiler/codegen/llvm/`: expression/body checking and textual LLVM IR emission.
6. `compiler/codegen/llvm/target.sole`: LLVM verification, optimization, and output.

The compiler currently lowers function bodies directly from tokens; it does not
have a separate AST or typed IR. `sole check file.sole` uses the same compilation
pipeline as `build`, including name/type checks and LLVM IR verification, without
linking or running the program. Imports must resolve, but no linker is needed.
The former `syntax` command and `--grammar` option have been removed; there is no
separate EBNF interpreter or syntax-only validation path.

LLVM performs optimization and machine-code generation. Runtime support stays in
`compiler/runtime/`; ordinary library code stays in `lib/`.

### Built-in C API

Use `¢.name` to call compiler-declared C functions without imports:

```sole
def main() -> int32:
    data: ptr = ¢.malloc(64)
    ¢.free(data)
    return ¢.abs(-7) - 7
```

Available functions and signatures are defined in `compiler/raw/c.sole`, including
libc, libm, POSIX, and dynamic-loader bindings. Names and argument types are checked
at compile time; arbitrary external symbols are not discovered automatically.
`¢` is a reserved namespace, not a value, and its members cannot be rebound.
Foreign pointer operations remain unsafe and follow the platform C ABI (currently
Linux x86-64 with glibc). Existing `import raw.c` calls remain supported.

LLVM is separate: use `import raw.llvm` and explicitly link the LLVM library when
calling it. Ordinary C API calls do not add an LLVM dependency to your executable.

Runtime implementation files live in `compiler/runtime/`, alongside the compiler
that owns their ABI. `lib/` contains the standard library; its internal
`import runtime.*` dependencies resolve through the compiler resource directory.

### Local Development

```sh
make up             # Setup the local development
make down           # Cleanup the local enviroment
```

To rebuild and verify self-hosting, then run the tests:

```sh
sh scripts/bootstrap-ci.sh
SOLE_COMPILER="$PWD/.build/sole" sh compiler/tests/suite.sh
```

Bootstrap compares the second and third compiler builds byte-for-byte. It also
supports older seeds that implicitly load the now-removed primitive method files.

### Formatting

Run `sole format file.sole` to format a file, or `sole format --check file.sole` to check without modifying it.

The formatter inserts `"""TODO: Document this function."""` in functions that lack a docstring. Existing docstrings and bodyless `extern` declarations are preserved. Every standalone `#` comment must have a blank line before it; inline comments and comment-like text inside strings are unchanged.
