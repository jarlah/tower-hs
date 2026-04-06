# http-tower-hs

Composable HTTP client middleware for Haskell, built on [tower-hs](https://hackage.haskell.org/package/tower-hs).

Provides HTTP-specific middleware: headers, request IDs, redirect following, response validation, OpenTelemetry tracing with HTTP semantic conventions, and logging.

Part of the [tower-hs](https://github.com/jarlah/tower-hs) mono-repo. See the repo README for full documentation and examples.

## Related packages

- [tower-hs](https://hackage.haskell.org/package/tower-hs) — Generic service middleware core
- [servant-tower-hs](https://hackage.haskell.org/package/servant-tower-hs) — Servant client middleware built on tower-hs
