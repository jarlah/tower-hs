# Changelog

## 0.2.0.0 — 2026-04-06

### Breaking Changes

- Refactored into multi-package mono-repo structure
- Generic middleware moved to `tower-hs` package: Retry, Timeout, CircuitBreaker, Filter, Hedge
- Core types moved to `tower-hs` package: `Service`, `Middleware`, `ServiceError`
- Removed modules: `Network.HTTP.Tower.Core`, `Network.HTTP.Tower.Error`, `Network.HTTP.Tower.Middleware.Retry`, `Network.HTTP.Tower.Middleware.Timeout`, `Network.HTTP.Tower.Middleware.CircuitBreaker`, `Network.HTTP.Tower.Middleware.Filter`, `Network.HTTP.Tower.Middleware.Hedge`

### Migration Guide

- Add `tower-hs` as a dependency
- Replace `Network.HTTP.Tower.Core` imports with `Tower.Service`
- Replace `Network.HTTP.Tower.Error` imports with `Tower.Error`
- Replace `Network.HTTP.Tower.Middleware.Retry` with `Tower.Middleware.Retry` (and similarly for Timeout, CircuitBreaker, Filter, Hedge)

## 0.1.0.0 — 2026-04-06

- Initial release
- HTTP client with TLS/mTLS support
- Middleware: Logging, SetHeader, RequestId, FollowRedirect, Validate, Tracing (OpenTelemetry with HTTP semantic conventions), TestDouble (withMockMap)
- `Network.HTTP.Tower` convenience re-export module
