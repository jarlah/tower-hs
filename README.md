# http-tower-hs

Composable HTTP client middleware for Haskell, inspired by Rust's [Tower](https://docs.rs/tower/latest/tower/).

The Haskell ecosystem has solid HTTP clients (`http-client`, `http-client-tls`) but no middleware composition story. Every project ends up hand-rolling retry logic, timeout handling, and logging around raw HTTP calls. `http-tower-hs` fixes this with a simple `Service`/`Middleware` abstraction.

## Quick start

```haskell
import Network.HTTP.Tower
import qualified Network.HTTP.Client as HTTP

main :: IO ()
main = do
  client <- newClient
  let configured = client
        |> withBearerAuth "my-api-token"
        |> withRequestId
        |> withRetry (constantBackoff 3 1.0)
        |> withTimeout 5000
        |> withValidateStatus (\c -> c >= 200 && c < 300)
        |> withTracing

  req <- HTTP.parseRequest "https://api.example.com/v1/users"
  result <- runRequest configured req
  case result of
    Left err   -> putStrLn $ "Failed: " <> show err
    Right resp -> putStrLn $ "OK: " <> show (HTTP.responseStatus resp)
```

## Core concepts

### Service

A function from request to `IO (Either ServiceError response)`:

```haskell
newtype Service req res = Service { runService :: req -> IO (Either ServiceError res) }
```

### Middleware

A function that wraps a service to add behavior:

```haskell
type Middleware req res = Service req res -> Service req res
```

### Client

An HTTP client with a middleware stack, built using the `(|>)` operator:

```haskell
client <- newClient
let configured = client
      |> withRetry (exponentialBackoff 5 0.5 2.0)
      |> withTimeout 3000
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

### Retry

Retries failed requests with configurable backoff:

```haskell
-- Constant: 3 retries, 1 second between each
client |> withRetry (constantBackoff 3 1.0)

-- Exponential: 5 retries, starting at 500ms, doubling each time
client |> withRetry (exponentialBackoff 5 0.5 2.0)
```

### Timeout

Fails with `TimeoutError` if the request exceeds the given milliseconds:

```haskell
client |> withTimeout 5000
```

### Logging

Logs method, host, status, and duration:

```haskell
client |> withLogging (\msg -> Data.Text.IO.putStrLn msg)
```

### Circuit Breaker

Three-state circuit breaker (Closed → Open → HalfOpen) using STM:

```haskell
breaker <- newCircuitBreaker
let configured = client
      |> withCircuitBreaker (CircuitBreakerConfig 5 30) breaker
```

Trips open after 5 consecutive failures, rejects immediately for 30 seconds, then probes recovery with one request.

### OpenTelemetry Tracing

Wraps each request in an OTel span with [stable HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/):

```haskell
-- Uses global TracerProvider (no-ops if unconfigured)
client |> withTracing

-- Or with a specific tracer
client |> withTracingTracer myTracer
```

Attributes: `http.request.method`, `server.address`, `server.port`, `url.full`, `http.response.status_code`, `error.type`.

### Set Header

Add headers to every request:

```haskell
client |> withBearerAuth "my-token"
client |> withUserAgent "my-app/1.0"
client |> withHeader "X-Custom" "value"
client |> withHeaders [("X-A", "1"), ("X-B", "2")]
```

### Request ID

Generate a UUID v4 correlation ID per request:

```haskell
client |> withRequestId                        -- X-Request-ID header
client |> withRequestIdHeader "X-Correlation-ID"  -- custom header name
```

### Follow Redirects

Automatically follow 3xx responses (301, 302, 303, 307, 308):

```haskell
client |> withFollowRedirects 5  -- max 5 hops
```

Respects 303 → GET method change per HTTP spec.

### Filter

Predicate-based request control:

```haskell
-- Only allow GET requests
client |> withFilter (\req -> HTTP.method req == "GET")

-- Don't retry 4xx responses (place between retry and base service)
client |> withNoRetryOn (\resp -> statusCode (responseStatus resp) < 500)
```

### Hedge

Speculative retry — if the primary request is slow, fire a second and return whichever finishes first:

```haskell
client |> withHedge 200  -- hedge after 200ms
```

Only use for idempotent requests (GET, etc.).

### Response Validation

Reject unexpected responses:

```haskell
-- Only accept 2xx
client |> withValidateStatus (\c -> c >= 200 && c < 300)

-- Require JSON
client |> withValidateContentType "application/json"

-- Require a specific header
client |> withValidateHeader "X-Request-ID"
```

### Test Doubles

Testing utilities — mock services, record requests:

```haskell
-- Replace the service entirely
let testClient = client |> withMock (\req -> pure (Right fakeResponse))

-- Route-based mocks
let mocks = Map.fromList
      [ ("api.example.com/v1/users", Right usersResponse)
      , ("api.example.com/v1/health", Right healthResponse)
      ]
let testClient = client |> withMockMap mocks

-- Record requests for assertions
recorder <- newIORef []
let testClient = client |> withRecorder recorder
_ <- runRequest testClient someRequest
recorded <- readIORef recorder
length recorded `shouldBe` 1
```

## Error handling

All errors are returned as `Either ServiceError Response` — no exceptions escape the middleware stack:

```haskell
data ServiceError
  = HttpError SomeException
  | TimeoutError
  | RetryExhausted Int ServiceError
  | CircuitBreakerOpen
  | CustomError Text
```

## Building

```bash
stack build
stack test
hlint src/ test/
```

## License

MIT
