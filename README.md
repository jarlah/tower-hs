# tower-hs

[![CI](https://github.com/jarlah/tower-hs/actions/workflows/ci.yml/badge.svg)](https://github.com/jarlah/tower-hs/actions/workflows/ci.yml)

Composable service middleware for Haskell, inspired by Rust's [Tower](https://docs.rs/tower/latest/tower/).

## Packages

| Package | Description | Hackage |
|---------|-------------|---------|
| **[tower-hs](tower-hs/)** | Generic `Service`/`Middleware` abstractions with protocol-agnostic middleware (retry, timeout, circuit breaker, filter, hedge, tracing, logging) | [![Hackage](https://img.shields.io/hackage/v/tower-hs.svg)](https://hackage.haskell.org/package/tower-hs) |
| **[http-tower-hs](http-tower-hs/)** | HTTP client middleware built on `tower-hs` (headers, redirects, tracing, validation, logging) | [![Hackage](https://img.shields.io/hackage/v/http-tower-hs.svg)](https://hackage.haskell.org/package/http-tower-hs) |
| **[servant-tower-hs](servant-tower-hs/)** | Servant `ClientMiddleware` adapter + servant-specific middleware (headers, request IDs, validation, tracing, logging) | [![Hackage](https://img.shields.io/hackage/v/servant-tower-hs.svg)](https://hackage.haskell.org/package/servant-tower-hs) |

## Quick start

### HTTP client (http-tower-hs)

Generic tower-hs middleware and HTTP-specific middleware compose with `(&)` and `(.)` from the standard library:

```haskell
import Data.Function ((&))
import Network.HTTP.Tower
import qualified Network.HTTP.Client as HTTP

main :: IO ()
main = do
  client <- newClient
  breaker <- newCircuitBreaker
  let config = CircuitBreakerConfig { cbFailureThreshold = 5, cbCooldownPeriod = 30 }
      configured = client & applyMiddleware
        ( -- Generic tower-hs middleware
          withRetry (exponentialBackoff 3 0.5 2.0)
        . withTimeout 5000
        . withCircuitBreaker config breaker
          -- HTTP-specific middleware
        . withBearerAuth "my-api-token"
        . withRequestId
        . withValidateStatus (\c -> c >= 200 && c < 300)
        . withLogging (Data.Text.IO.putStrLn)
        . withTracing
        )

  req <- HTTP.parseRequest "https://api.example.com/v1/users"
  result <- runRequest configured req
  case result of
    Left err   -> putStrLn $ "Failed: " <> show err
    Right resp -> putStrLn $ "OK: " <> show (HTTP.responseStatus resp)
```

> **Note:** tower-hs also provides a `(|>)` operator for a Rust/Elixir-style left-to-right syntax:
> ```haskell
> configured = client
>       |> withRetry (exponentialBackoff 5 0.5 2.0)
>       |> withTimeout 3000
> ```

### Servant client (servant-tower-hs)

Generic tower-hs middleware and servant-specific middleware compose in a single stack:

```haskell
import Data.Function ((&))
import Servant.Tower.Adapter (withTowerMiddleware)
import Tower.Middleware.Retry (withRetry, exponentialBackoff)
import Tower.Middleware.Timeout (withTimeout)
import Tower.Middleware.CircuitBreaker
import Servant.Tower.Middleware.SetHeader (withBearerAuth, withUserAgent)
import Servant.Tower.Middleware.Validate (withValidateStatus)
import Servant.Tower.Middleware.Logging (withLogging)
import Servant.Tower.Middleware.Tracing (withTracing)

breaker <- newCircuitBreaker
let config = CircuitBreakerConfig { cbFailureThreshold = 5, cbCooldownPeriod = 30 }
    env = mkClientEnv manager baseUrl & withTowerMiddleware
      ( -- Generic tower-hs middleware
        withRetry (exponentialBackoff 3 0.5 2.0)
      . withTimeout 5000
      . withCircuitBreaker config breaker
        -- Servant-specific middleware
      . withBearerAuth "my-api-token"
      . withUserAgent "my-app/1.0"
      . withValidateStatus (\c -> c >= 200 && c < 300)
      . withLogging (Data.Text.IO.putStrLn)
      . withTracing
      )
result <- runClientM (getUsers <|> getHealth) env
```

### Generic service (tower-hs)

`tower-hs` is not tied to HTTP -- it works with any `req -> IO (Either ServiceError res)` service. Wrap a database client, a gRPC stub, a message queue, or anything else:

```haskell
import Data.Function ((&))
import Tower

-- Wrap a database query as a Service
let dbService :: Service SQL.Query [SQL.Row]
    dbService = Service $ \query -> do
      result <- try $ SQL.query conn query
      pure $ case result of
        Left  err  -> Left (TransportError err)
        Right rows -> Right rows

-- Add resilience with the same middleware you'd use for HTTP
breaker <- newCircuitBreaker
let config = CircuitBreakerConfig { cbFailureThreshold = 5, cbCooldownPeriod = 30 }
    robust = dbService
           & withCircuitBreaker config breaker
           & withTimeout 5000
           & withRetry (exponentialBackoff 3 0.5 2.0)

result <- runService robust "SELECT * FROM users"
```

## Core concepts

### Service

A function from request to `IO (Either ServiceError response)`:

```haskell
newtype Service req res = Service { runService :: req -> IO (Either ServiceError res) }
```

`Service` is a `Functor` (transform responses with `fmap`) and a `Profunctor` (transform both request and response types with `dimap`). This is useful for adapting a generic service to a domain-specific API:

```haskell
import Data.Function ((&))
import Data.Profunctor (dimap)

-- Start with a raw HTTP service
let httpSvc :: Service HTTP.Request (HTTP.Response LBS.ByteString)

-- Adapt to your domain types
let userSvc :: Service UserId User
    userSvc = dimap toHttpRequest parseUser httpSvc

-- Or use the named helpers (same thing, more discoverable):
let userSvc' = dimapService toHttpRequest parseUser httpSvc
```

#### Arrow composition

`Service` is a `Category`, `Arrow`, and `ArrowChoice`, so you can chain services
with `>>>`, lift pure functions with `arr`, and route with `|||`. Errors
short-circuit automatically at each `>>>` step.

```haskell
let pipeline :: Service Request Response
    pipeline = authenticate >>> rateLimit >>> classify >>> (resilientAdmin ||| handleUser)
```

See [`examples/arrow-pipeline/`](examples/arrow-pipeline/) for a full working example
with sequential composition, data threading via `second`, and `ArrowChoice` routing.

### Middleware

A function that wraps a service to add behavior:

```haskell
type Middleware req res = Service req res -> Service req res
```

### Client

An HTTP client with a middleware stack, built using `(&)` and `applyMiddleware`:

```haskell
import Data.Function ((&))

client <- newClient
let configured = client & applyMiddleware
      ( withRetry (exponentialBackoff 5 0.5 2.0)
      . withTimeout 3000
      )
```

### TLS / mTLS

`newClient` uses HTTPS by default. For custom CA certificates or client certificate authentication (mTLS):

```haskell
-- Custom CA (e.g., internal PKI)
client <- newClientWithTLS (Just "certs/ca.pem") Nothing

-- mTLS (client certificate authentication)
client <- newClientWithTLS
  (Just "certs/ca.pem")
  (Just ("certs/client.pem", "certs/client-key.pem"))

-- System CA store, no client cert (same as newClient)
client <- newClientWithTLS Nothing Nothing
```

For full control, use `newClientWith` with custom `ManagerSettings`.

## Middleware

### Generic (tower-hs)

| Middleware | Description |
|-----------|-------------|
| `withRetry` | Retry with constant or exponential backoff |
| `withTimeout` | Fail after N milliseconds |
| `withCircuitBreaker` | Three-state circuit breaker (Closed/Open/HalfOpen) via STM |
| `withFilter` | Predicate-based request filtering |
| `withNoRetryOn` | Prevent retry on matching responses |
| `withHedge` | Speculative retry via async race |
| `withLogging` | Generic timed logging with user-provided formatter |
| `withTracingConfig` | OpenTelemetry tracing with configurable span name/attributes |
| `withTracingGlobal` | OTel tracing using global TracerProvider |
| `withValidate` | Generic response validation with user-provided check |
| `withMapRequest` | Transform request with IO before forwarding |
| `withMapRequestPure` | Transform request with pure function before forwarding |
| `withMock` | Replace service with mock (testing) |
| `withRecorder` | Record requests (testing) |

### HTTP-specific (http-tower-hs)

| Middleware | Description |
|-----------|-------------|
| `withLogging` | Log method, host, status, duration |
| `withBearerAuth` | Add Authorization: Bearer header |
| `withHeader` / `withHeaders` | Add custom headers |
| `withUserAgent` | Set User-Agent header |
| `withRequestId` | Add UUID v4 X-Request-ID header |
| `withFollowRedirects` | Follow 3xx responses (301-308) |
| `withValidateStatus` | Reject unexpected status codes |
| `withValidateContentType` | Require specific Content-Type |
| `withValidateHeader` | Require specific response header |
| `withTracing` | OpenTelemetry spans with HTTP semantic conventions |
| `withMockMap` | Route-based mock responses (testing) |

### Servant-specific (servant-tower-hs)

| Middleware | Description |
|-----------|-------------|
| `withBearerAuth` | Add Authorization: Bearer header |
| `withHeader` / `withHeaders` | Add custom headers |
| `withUserAgent` | Set User-Agent header |
| `withRequestId` | Add UUID v4 X-Request-ID header |
| `withValidateStatus` | Reject unexpected status codes |
| `withValidateContentType` | Require specific Content-Type |
| `withValidateHeader` | Require specific response header |
| `withTracing` | OpenTelemetry spans with HTTP semantic conventions |
| `withLogging` | Log method, status, duration |

All generic tower-hs middleware (retry, timeout, circuit breaker, etc.) also works with servant via `withTowerMiddleware`.

## Error handling

All errors are returned as `Either ServiceError Response` — no exceptions escape the middleware stack:

```haskell
data ServiceError
  = TransportError SomeException
  | TimeoutError
  | RetryExhausted Int ServiceError
  | CircuitBreakerOpen
  | CustomError Text
```

## Showcase

| Project | Description |
|---------|-------------|
| **[Sentinel](https://github.com/jarlah/sentinel)** | Programmable infrastructure health monitor distributed as a single Haskell binary. Monitors HTTP endpoints and databases (PostgreSQL, MySQL, Redis) with scheduled probes, circuit breakers, retries, and alerting (Slack, email, Prometheus). Built on `tower-hs` and `http-tower-hs`. |

## Building

```bash
stack build         # all packages
stack test          # all tests
stack build tower-hs            # just the core
stack test http-tower-hs        # just HTTP tests
stack test servant-tower-hs     # just servant adapter tests
```

## License

MIT
