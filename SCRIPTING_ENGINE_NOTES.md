# Scripting Engine Improvement Notes

## Interop consistency
- Value width mismatch: returning I64 for `int` causes confusion in Unity. Clarify type mapping and normalize in the C# wrapper.
- Expose helpers to convert return values safely (`AsI32`, `AsI64`, `AsF32`, `AsF64`) with explicit checks.
- Provide a strict vs tolerant mode in the wrapper for debugging type issues.

## API ergonomics
- Add helpers for common host patterns: script loading, compile+run, module caching.
- Add helpers to bind Unity object handles and validate lifetime/ownership.
- Provide a typed export lookup (discoverable exports with signatures).

## Error reporting
- Ensure `TakeLastError` is thread-safe and scoped to the calling engine/context.
- Include richer error data (line/column, stack trace, error category).

## Performance
- Provide bulk call APIs to reduce per-call allocations.
- Add pooling for temporary arrays/strings in the Unity wrapper.

## Safety and threading
- Document thread-safety (engine vs world vs context) explicitly.
- Add guardrails for calling after dispose (clearer error messages).

## Packaging and build
- Document supported platforms and required toolchains.
- Provide consistent debug/release binaries per platform.

