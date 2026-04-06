# servant-tower-hs

Use [tower-hs](https://hackage.haskell.org/package/tower-hs) middleware with [servant](https://hackage.haskell.org/package/servant-client) clients.

Provides an adapter bridging tower-hs middleware to servant's `ClientMiddleware`, plus servant-native middleware: headers, request IDs, response validation, OpenTelemetry tracing, and logging.

Part of the [tower-hs](https://github.com/jarlah/tower-hs) mono-repo. See the repo README for full documentation and examples.

## Related packages

- [tower-hs](https://hackage.haskell.org/package/tower-hs) — Generic service middleware core
- [http-tower-hs](https://hackage.haskell.org/package/http-tower-hs) — HTTP client middleware built on tower-hs
