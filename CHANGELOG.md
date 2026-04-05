# Changelog

## 0.1.0.0 — 2026-04-05

Initial release.

### Client
- `newClientWithTLS` — custom CA certificates and mTLS (client certificate authentication)

### Middleware
- **Retry** — constant and exponential backoff
- **Timeout** — millisecond-level request timeouts
- **Logging** — pluggable request/response logging
- **Circuit Breaker** — three-state (Closed/Open/HalfOpen) using STM
- **OpenTelemetry Tracing** — automatic spans with stable HTTP semantic conventions
- **Set Header** — add headers, Bearer auth, User-Agent
- **Request ID** — UUID v4 correlation IDs
- **Follow Redirect** — automatic 3xx redirect following
- **Filter** — predicate-based request filtering
- **Hedge** — speculative retry via async race
- **Validate** — status code, Content-Type, header validation
- **Test Double** — mock services, route-based mocks, request recorder
