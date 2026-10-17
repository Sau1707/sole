# Sole

A statically typed, indentation-based language with an LLVM backend. It compiles to **native executables**.


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

### String methods

Strings provide `starts_with(prefix)`, `ends_with(suffix)`, `find(needle)`,
`contains(needle)`, `replace(old, new)`, `partition(separator)`, and `repeat(count)`
without an import:

```sole
"Hello, Sole!".contains("Sole")
"ha".repeat(3)
```

Matching is byte-based, and `find` returns a byte offset or `-1` when absent.
An empty needle matches at offset zero. `replace` replaces non-overlapping matches
and leaves the string unchanged for an empty pattern. `partition` returns
`[before, separator, after]` at the first match, or `[text, "", ""]` for an absent
or empty separator. `repeat` returns an empty string for nonpositive counts.

### Numeric, byte, and array methods

All signed and unsigned integer widths and both floating-point types provide
`abs()`, `min(other)`, `max(other)`, and `clamp(lower, upper)`. Integers also provide
`gcd(other)`. Arguments and results retain the receiver's type; no numeric widening
is implied. Integer and real literal receivers default to `int64` and `float64`.

```sole
int32(-12).abs()
uint64(48).gcd(18)
float32(2.5).clamp(0.0, 2.0)
b'A'.to_lower().is_alpha()
```

`clamp` applies `max(lower)` followed by `min(upper)`, including for reversed
bounds. Signed integer `abs` uses wrapping negation, so the minimum value remains
unchanged. Signed `gcd` preserves the former `math.gcd` algorithm and its ordinary
integer arithmetic checks; results outside the signed positive range are not
widened. Floating `abs` negates strictly negative values and preserves signed zero
and NaNs. Floating `min`/`max` use strict comparisons and return the argument on
ties or unordered comparisons, rather than IEEE `minimum`/`maximum` semantics.

Bytes (`uint8`) also provide ASCII-only `is_digit()`, `is_alpha()`, `is_space()`,
`to_lower()`, and `to_upper()`. Non-ASCII bytes are left unchanged by conversions.

Dynamic string arrays (`str[]`) provide `contains(value)` and `index_of(value)`.
Search returns the first matching index, or `-1` when absent, without modifying
the array. These methods preserve the former string-array-only API; other array
element types are not implicitly supported.

These methods require no imports. The former `math`, `ascii`, and `arrays`
modules have been removed. `bisect` and `statistics` remain separate modules.

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

### Formatting

Run `sole format file.sole` to format a file, or `sole format --check file.sole` to check without modifying it.

The formatter inserts `"""TODO: Document this function."""` in functions and methods that lack a docstring. Existing docstrings and bodyless `extern` declarations are preserved. Every standalone `#` comment must have a blank line before it; inline comments and comment-like text inside strings are unchanged.
