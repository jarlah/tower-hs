# tower-hs

Composable service middleware for Haskell, inspired by Rust's [Tower](https://docs.rs/tower/latest/tower/).

Generic `Service`/`Middleware` abstractions with protocol-agnostic middleware: retry, timeout, circuit breaker, filter, hedge, tracing (OpenTelemetry), logging, validation, request transformation, and test doubles.

Part of the [tower-hs](https://github.com/jarlah/tower-hs) mono-repo. See the repo README for full documentation and examples.

## Related packages

- [http-tower-hs](https://hackage.haskell.org/package/http-tower-hs) — HTTP client middleware built on tower-hs
- [servant-tower-hs](https://hackage.haskell.org/package/servant-tower-hs) — Servant client middleware built on tower-hs
