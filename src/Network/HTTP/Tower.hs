-- | Composable HTTP client middleware for Haskell, inspired by Rust's Tower.
--
-- @
-- client <- newClient
-- let configured = client
--       |> withRetry (constantBackoff 3 1.0)
--       |> withTimeout 5000
--       |> withLogging (putStrLn . unpack)
--
-- result <- runRequest configured request
-- case result of
--   Left err   -> putStrLn $ "Failed: " <> show err
--   Right resp -> putStrLn $ "OK: " <> show (responseStatus resp)
-- @
module Network.HTTP.Tower
  ( -- * Core types
    Service(..)
  , Middleware
  , mapService
  , composeMiddleware
    -- * Client
  , Client(..)
  , HttpResponse
  , newClient
  , newClientWith
  , runRequest
  , applyMiddleware
  , (|>)
    -- * Errors
  , ServiceError(..)
  , displayError
    -- * Middleware
    -- ** Retry
  , BackoffStrategy(..)
  , constantBackoff
  , exponentialBackoff
  , withRetry
    -- ** Timeout
  , withTimeout
    -- ** Logging
  , withLogging
  , withLoggingCustom
    -- ** Circuit Breaker
  , CircuitBreakerConfig(..)
  , CircuitBreakerState(..)
  , CircuitBreaker
  , newCircuitBreaker
  , withCircuitBreaker
  , getCircuitBreakerState
    -- ** Tracing (OpenTelemetry)
  , withTracing
  , withTracingTracer
  ) where

import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Client
import Network.HTTP.Tower.Error
import Network.HTTP.Tower.Middleware.Retry
import Network.HTTP.Tower.Middleware.Timeout
import Network.HTTP.Tower.Middleware.Logging
import Network.HTTP.Tower.Middleware.CircuitBreaker
import Network.HTTP.Tower.Middleware.Tracing
