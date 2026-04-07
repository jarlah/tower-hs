# Changelog

## 0.2.0.0 — 2026-04-07

- Add `Functor` instance for `Service req` — use `fmap` to transform successful responses
- Add `Profunctor` instance for `Service` — use `dimap`/`lmap` to adapt request and response types
- Add `contramapService` and `dimapService` as named synonyms for `lmap` and `dimap`
- `mapService` is now a synonym for `fmap`
- New dependency: `profunctors`
- Adopt `(&)` from `Data.Function` as idiomatic style in docs, tests, and examples

## 0.1.0.0 — 2026-04-06

- Initial release
- Core `Service`/`Middleware` abstractions
- Middleware: Retry, Timeout, CircuitBreaker, Filter, Hedge, Logging, Tracing (OpenTelemetry), Validate, Transform, TestDouble
- `Tower.Error.Testing` module with shared `Eq ServiceError` instance
