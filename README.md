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

### Local Development

```sh
make up             # Setup the local development
make down           # Cleanup the local enviroment
```

### Formatting

Run `sole format file.sole` to format a file, or `sole format --check file.sole` to check without modifying it.

The formatter inserts `"""TODO: Document this function."""` in functions and methods that lack a docstring. Existing docstrings and bodyless `extern` declarations are preserved. Every standalone `#` comment must have a blank line before it; inline comments and comment-like text inside strings are unchanged.
