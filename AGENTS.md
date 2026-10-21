# Sole Compiler Engineering

Sole is a Python-inspired programming language. Treat it as a production-grade compiler: prioritize correctness, soundness, clear architecture, precise diagnostics, determinism, and maintainability over implementation convenience or performance shortcuts.

Choose the simplest correct design that solves a concrete problem. Use established compiler techniques where justified; do not add abstractions, dependencies, IR layers, or advanced machinery merely because other compilers use them.

## Workflow and Scope

1. Inspect relevant modules, dependencies, tests, documentation, and architectural conventions before editing. Establish behavior from source rather than guessing.
2. Trace the affected construct through the compiler pipeline and verify its intended semantics.
3. For bugs, reproduce the smallest meaningful failure, identify the earliest incorrect phase, and examine related constructs for the same defect.
4. Make the smallest architecturally correct change in the subsystem that owns the responsibility. Reuse existing mechanisms; avoid example-specific fixes and unrelated refactoring.
5. Update all affected phases, diagnostics, tests, and documentation. Assess performance and compatibility implications.
6. Run relevant verification and regression tests. Report what was verified, assumptions, limitations, and anything left untested.

Explain the consequences of breaking architectural changes. Provide complete updated code when explicitly requested.

Do not create Markdown files or add new content to existing Markdown files unless explicitly requested. Otherwise, limit Markdown edits to minor corrections.

## Language Semantics

- Sole's specification is authoritative. Do not assume CPython syntax, behavior, memory management, or implementation details apply unless explicitly adopted.
- Preserve backward compatibility unless a language change is intentionally approved. Identify unspecified behavior before making permanent semantic decisions; do not invent features, syntax, or runtime behavior without justification and authorization.
- Define relevant evaluation order, scope, binding, mutability, identity, lifetime, operators, calls, control flow, exceptions, and imports explicitly.
- Specify coercions, conversions, truthiness, equality, and numeric behavior independently of implementation details.
- Distinguish syntax, name-resolution, type, and runtime errors.
- A feature is complete only when its defined scope works end to end, including applicable parsing, analysis, IR, lowering, optimization, code generation, runtime, diagnostics, tooling, documentation, and tests—not merely when parsing succeeds.

## Architecture and Representations

Reference pipeline, not a requirement to introduce every representation:

```text
Source → Lexer → Parser → AST → Name Resolution → Semantic Analysis
       → HIR → MIR → Optimization → Backend Lowering → Code Generation
```

- Define each phase's inputs, outputs, responsibilities, and invariants. Keep parsing, semantic analysis, optimization, and code generation separate.
- Implement semantics in the appropriate analysis or lowering phase, not opportunistically in code generation. Never bypass required phases to make an example compile.
- Isolate target-specific behavior from target-independent analysis and avoid coupling the frontend to a backend or architecture.
- Keep interfaces explicit and stable where needed without unnecessarily freezing experimental details.
- ASTs must faithfully represent syntax with explicit node variants and source spans, separate from semantic meaning and backend details.
- Define each IR's abstraction level, valid nodes, types, control-flow invariants, ownership, lifetimes, permitted transformations, and verification requirements.
- Use typed IR, CFGs, SSA, dominance, data-flow analysis, or related techniques when they materially improve correctness or optimization. Verify invariants near their origin and after transformations in debug and test configurations.

## Frontend and Semantic Analysis

- Lex deterministically with accurate spans, lines, and columns. Follow Sole's Unicode, indentation, whitespace, and token rules; avoid unnecessary token allocations.
- Use a parsing strategy appropriate to the grammar with explicit precedence and associativity. Produce valid ASTs, preserve spans, and reject malformed or unsupported syntax gracefully. Recover from errors where useful without misleading cascades.
- Resolve names and symbols deterministically with well-defined lexical scopes, duplicate-declaration checks, and consistent shadowing.
- Separate compile-time and runtime type checks. Permit implicit conversions only where specified, preserve type information through relevant lowering stages, and avoid unsound assumptions about values or control flow.
- If supported, use a well-defined inference strategy, preserve dynamic typing behavior, and define generic/protocol/trait/specialization resolution before optimizing it. Do not introduce static typing merely to simplify code generation.

## Optimization, Backend, and Runtime

- Transformations must preserve observable behavior unless the specification explicitly permits otherwise. Respect side effects, exceptions, evaluation order, aliasing, integer overflow, floating-point behavior, and memory semantics.
- Give optimization passes canonical IR forms and explicit preconditions and postconditions. Use speculation only with proven assumptions or appropriate guards; test edge cases and semantic preservation.
- Generate code from verified representations. Respect calling conventions, ABI, type layout, alignment, memory access, calls, returns, and control flow. Emit useful debugging information when supported.
- Follow established backend contracts and verification mechanisms rather than recreating backend infrastructure without a compelling reason. Validate emitted code through executable tests.
- Define compiler/runtime interfaces, object representation, ownership, allocation, lifetimes, and runtime invariants explicitly. Specify heap allocation, dynamic dispatch, exceptions, and automatic memory management where supported; choose memory management to fit Sole's semantics and prevent memory-unsafe behavior.

## Diagnostics and Error Handling

- Produce accurate, specific, understandable, actionable diagnostics with precise source locations. Preserve meaningful spans across phases; use diagnostic codes or categories where useful and distinguish errors, warnings, and notes.
- Treat malformed source and external inputs as expected validation cases. Handle unsupported configurations safely; do not substitute assertions for user-input validation.
- Separate recoverable source errors from compiler defects. Never present an internal compiler bug as a source error or expose raw internal exceptions as ordinary diagnostics.
- Check invariants at meaningful phase boundaries. Report internal failures with useful developer context; do not hide them with broad exception handling, suppress them to imply success, or continue with corrupted state.

## Testing and Verification

- Add tests proportionate to every compiler change: unit tests for components, integration tests for phase interactions, and end-to-end tests checking output, exit status, and observable behavior.
- Test both valid and invalid syntax and verify rejection diagnostics. Every confirmed compiler bug needs a regression test that fails before the fix and passes afterward.
- Cover relevant empty inputs, boundaries, Unicode, recursion, nested scopes, and error paths. Keep tests deterministic unless nondeterminism is the subject.
- Use fuzzing, property-based tests, generated programs/ASTs, IR verifier tests, and metamorphic tests where practical. Differential testing is valid only when reference semantics match Sole's.
- Never delete failing tests, weaken assertions, or replace behavioral coverage with superficial checks to obtain a passing suite.
- Affected tests must pass before a change is complete. Never claim compilation, testing, or benchmarking that did not occur, or represent untested behavior as proven correct. Explicitly report verification that could not be performed.

## Performance and Caching

- Measure compiler and generated-program performance separately using reproducible, representative benchmarks. Establish baselines, profile before major optimization, distinguish meaningful changes from noise, and document trade-offs. Make no performance claims without measurements.
- Consider compilation latency, memory, throughput, pass duration, incremental cost, and binary size, alongside runtime latency, memory, allocations, startup, and call overhead. Do not optimize synthetic microbenchmarks at the expense of real workloads.
- Introduce incremental compilation and caching only with sound dependency tracking, stable identities, and invalidation. Cached and clean builds must be semantically equivalent; make corruption and version mismatches recoverable. Prefer correct full compilation over incorrect incremental behavior.

## Code Quality and Completion

- Follow existing naming and style. Keep functions focused, modules cohesive, contracts explicit, and data structures expressive of valid states. Avoid monolithic passes, mutable global state, circular dependencies, and duplicated logic across phases.
- Prefer established algorithms unless a custom approach has a measurable or architectural advantage. Document non-obvious algorithms and invariants without redundant commentary.
- A change is complete when intended behavior is understood, affected phases and documentation are updated, invariants and compatibility are preserved, relevant edge cases and diagnostics are covered, affected tests pass, and verification results and remaining limitations are reported accurately.
