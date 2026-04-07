# Changelog

## 0.1.1.0 — 2026-04-07

- Adopt `(&)` from `Data.Function` as idiomatic style in tests and examples
- Requires `tower-hs >= 0.2.0.0`

## 0.1.0.0 — 2026-04-06

- Initial release
- `Servant.Tower.Adapter`: bridge tower-hs middleware to servant's `ClientMiddleware`
- Servant-specific middleware: SetHeader, RequestId, Validate, Tracing (OpenTelemetry), Logging
