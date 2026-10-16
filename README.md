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

Local development uses the published compiler at `~/.local/bin/sole`, never a
locally built compiler. `make install` installs the release;
`make format` uses it without rebuilding the compiler.
CI bootstraps source releases separately.

`sole syntax file.sole ...` validates syntax without type checking or linking,
using the bundled EBNF grammar. `--grammar path.ebnf` selects another grammar.

See [language features](docs/language-features.md) for additions available in source builds.
