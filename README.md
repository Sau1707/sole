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

### Local Development

```sh
make up             # Setup the local development
make down           # Cleanup the local enviroment
```

### Formatting

Run `sole format file.sole` to format a file, or `sole format --check file.sole` to check without modifying it.

The formatter inserts `"""TODO: Document this function."""` in functions and methods that lack a docstring. Existing docstrings and bodyless `extern` declarations are preserved. Every standalone `#` comment must have a blank line before it; inline comments and comment-like text inside strings are unchanged.
