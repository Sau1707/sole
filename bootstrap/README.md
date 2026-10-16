# Native bootstrap seed

`sole` is a Linux x86-64 Sole-built compiler. The bundled seed requires the
`libLLVM.so.21.1` ABI, glibc, and LLVM's shared-library dependencies. Building
executables also requires a C compiler driver, assembler, and linker.

`SHA256SUMS` records the seed's checksum. `../bootstrap.sh --seed` verifies it,
builds three compiler generations, and requires stages 2 and 3 to be identical.
No interpreter or Python package is used. Like any bootstrapping compiler, the
native seed is a trusted binary input, not a source-only bootstrap.

Use `SOLE_BOOTSTRAP=/absolute/path/to/sole ../bootstrap.sh` with another compatible
native compiler. `SOLE_LLVM_LIB` selects the LLVM library used by newly linked
compilers; it does not change the bundled seed's shared-library requirements.

To refresh the seed after a verified rebuild, from the repository root:

```sh
install -m 755 .build/sole bootstrap/sole
sha256sum bootstrap/sole > bootstrap/SHA256SUMS
./bootstrap.sh --seed
```
