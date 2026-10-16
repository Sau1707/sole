# Standard-library utilities

Import these modules by name (`import strings`, `import files`, etc.).

## Pure helpers

- `strings.replace(text, old, new)` replaces non-overlapping byte matches. An
  empty `old` leaves the input unchanged.
- `strings.partition(text, separator)` returns `[before, separator, after]` for
  the first match, or `[text, "", ""]` for an absent or empty separator.
- `arrays.index_of(items, value)` searches a `str[]`, returning the first index
  or `-1`. `arrays.contains(items, value)` returns membership without mutation.
- `os.path.split(path)` returns `[directory, basename]`, retaining the directory's
  trailing slash and performing no normalization. With no slash the directory
  is empty; with a trailing slash the basename is empty.
- `os.path.replace_suffix(path, suffix, replacement)` replaces a nonempty suffix
  only when a nonempty prefix precedes it; otherwise it appends the replacement.
  For example, `(".sole", ".sole", ".o")` produces `".sole.o"`.

Strings and path operations use byte offsets, not Unicode character indices.

## Filesystem

`files.is_file(path)` follows symlinks and returns false for missing paths or
non-regular files. `files.realpath(path)` returns a canonical absolute path and
exits on resolution failure. `files.same_file(a, b)` compares filesystem identity,
following symlinks; it returns false if either path cannot be resolved.

`files.atomic_write(path, contents)` returns an empty string on success or an
error message. It replaces an **existing regular file**, follows symlinks without
replacing the link, preserves destination permissions, and refuses multiple hard
links. It does not create missing files. Contents may contain embedded NUL bytes.

## Processes

`process.run(executable, arguments)` runs synchronously, without a shell.
`arguments` excludes `argv[0]`. Names without slashes are searched on `PATH`;
environment and standard streams are inherited. Empty executables and embedded
NULs in executable names or arguments are rejected.

The returned `process.Result` contains:

- `error`: nonempty on launch or wait failure; `exit_code` is `-1`, `signal` is `0`.
- `exit_code`: the child's exit status on normal completion; `signal` is `0`.
- `signal`: the terminating signal on abnormal completion; `exit_code` is `-1`.

No shell expansion, pipelines, redirections, or implicit script interpretation
occur. Executable scripts must have a shebang. The compiler's `SOLE_CC` setting
continues to name a single executable, not a command plus flags.
