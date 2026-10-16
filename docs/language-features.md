# Source-build language additions

These features are available starting with Sole 0.0.5. The compiler's own
source retains bootstrap-seed-compatible syntax; adopting the additions there
requires a separate seed refresh. Earlier releases do not support them.

## Byte literals

`b'A'` and `b"A"` produce a `uint8`. Exactly one decoded byte is required.
Supported escapes are `\n`, `\r`, `\t`, `\0`, `\\`, `\'`, and `\"`.
Empty, multibyte UTF-8, multiline, and triple-quoted byte literals are rejected.
Other numeric types require an explicit cast, for example `int32(b'A')`.

## Named record constructors

```sole
struct Pair:
    first: int32
    second: int32


def example() -> Pair:
    return Pair(second=2, first=1)
```

Struct and class arguments evaluate once in source order, then go into their
declared fields. A positional prefix is allowed: `Pair(1, second=2)`. Positional
arguments cannot follow named arguments. Each field must be supplied exactly
once, with its declared type; there are no defaults. Numeric and array literals
use the field's type as context. Functions, methods, and union variants remain
positional.

## Enums, tagged unions, and exhaustive matching

```sole
enum Kind:
    Number
    Empty


union Item:
    Number(value: int64)
    Empty()


def number(item: Item) -> int64:
    match item:
        case Item.Number(value):
            return value
        case Item.Empty():
            return 0
```

Construct values with `Kind.Number`, `Item.Number(42)`, and `Item.Empty()`.
Enum patterns use `case Kind.Number:` without parentheses. Every member or
variant must appear exactly once. Match subjects evaluate once, cases do not
fall through, and bindings are mutable copies local to their case. Copies of
class or growable-array payloads retain those types' shared-reference behavior.
`break` and `continue` target the enclosing loop. An exhaustive match terminates
control flow only when every case terminates.

Enums and unions are nominal: separately declared types remain distinct.
Enums support only same-type `==` and `!=`, with no numeric casts, arithmetic,
ordering, or assigned discriminants. Union payloads are accessible only through
matching; unions do not support comparison. Patterns initially allow only
positional identifier bindings, not guards, nesting, literal patterns, or wildcard
arms. Bindings cannot shadow active locals, declarations, or module namespaces.

Declarations must be nonempty and names must be unique. Payloads cannot be
`void`. Inline recursive layouts, including cycles through structs and fixed
arrays, are rejected; classes and growable arrays provide existing indirection.
The internal literal-type names `integer` and `real` cannot be declared as types.
Enums and unions are not supported in foreign signatures. Their representation
is an implementation detail, not a stable foreign ABI; invalid match tags trap.

## Range loops and numeric-local `+=`

```sole
def sum_to(stop: int64) -> int64:
    total: int64 = 0
    for i in range(stop):
        total += i
    return total
```

`range(stop)` starts at zero; `range(start, stop)` starts at `start`. Bounds must
have type `int64`, evaluate once in source order, and define a half-open range
with step one. Negative bounds are allowed; `start >= stop` gives no iterations.
Steps and general iterable loops are not supported. `range` is special syntax
only after `in`; ordinary functions may still use that name.

The loop variable is scoped to the loop and cannot shadow an active local.
Assigning to it affects only the current body, not the iteration sequence.
`continue` advances to the next iteration; `break` exits the loop.

`total += value` follows the same typing and arithmetic rules as
`total = total + value`, including existing integer wrapping behavior. Initially
only numeric local identifiers are supported, not fields, array elements,
nonnumeric locals, or other augmented operators.
