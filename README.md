# Sole

A statically typed, indentation-based language with an LLVM backend. It compiles to **native executables**.


## Install the released compiler

```sh
curl -fsSL https://raw.githubusercontent.com/Sau1707/sole/main/install.sh | sh
```

Supports Linux x86-64 with glibc 2.39 or newer (for example, Ubuntu 24.04).
LLVM and its non-glibc shared-library dependencies are bundled. The installer
installs missing native C build tools using apt, dnf/yum, pacman, or zypper,
requesting sudo access when needed. Other systems must provide these tools manually.

Sole installs into `~/.local`; add `~/.local/bin` to your `PATH`.
To disable automatic system package installation, use
`curl -fsSL https://raw.githubusercontent.com/Sau1707/sole/main/install.sh | SOLE_INSTALL_DEPS=0 sh`.
`SOLE_CC` selects an existing C compiler. `DESTDIR` stages files without installing
system packages or checking the host C toolchain. Third-party notices are included
under `share/sole/licenses`.


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
make test           # Run the tests cases
make down           # Cleanup the local enviroment
```
