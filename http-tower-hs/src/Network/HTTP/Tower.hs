-- |
-- Module      : Network.HTTP.Tower
-- Description : Composable HTTP client middleware for Haskell
-- License     : MIT
--
-- Inspired by Rust's <https://docs.rs/tower/latest/tower/ Tower> crate.
-- Build composable middleware stacks for HTTP clients with the @('|>')@ operator.
--
-- @
-- import Network.HTTP.Tower
-- import qualified Network.HTTP.Client as HTTP
--
-- main :: IO ()
-- main = do
--   client <- 'newClient'
--   let configured = client
--         '|>' 'withBearerAuth' \"my-token\"
--         '|>' 'withRequestId'
--         '|>' 'withRetry' ('constantBackoff' 3 1.0)
--         '|>' 'withTimeout' 5000
--         '|>' 'withValidateStatus' (\\c -> c >= 200 && c < 300)
--         '|>' 'withTracing'
--
--   req <- HTTP.parseRequest \"https://api.example.com/v1/users\"
--   result <- 'runRequest' configured req
--   case result of
--     Left err   -> putStrLn $ \"Failed: \" \<> show err
--     Right resp -> putStrLn $ \"OK: \" \<> show (HTTP.responseStatus resp)
-- @
--
-- All errors are returned as @'Either' 'ServiceError' response@ — no exceptions
-- escape the middleware stack.
module Network.HTTP.Tower
  ( -- * Core types (re-exported from tower-hs)
    Service(..)
  , Middleware
  , mapService
  , composeMiddleware
    -- * Client
  , Client(..)
  , HttpResponse
  , newClient
  , newClientWith
  , newClientWithTLS
  , runRequest
  , applyMiddleware
  , (|>)
    -- * Errors (re-exported from tower-hs)
  , ServiceError(..)
  , displayError
    -- * Middleware
    -- ** Retry (re-exported from tower-hs)
  , BackoffStrategy(..)
  , constantBackoff
  , exponentialBackoff
  , withRetry
    -- ** Timeout (re-exported from tower-hs)
  , withTimeout
    -- ** Logging
  , withLogging
  , withLoggingCustom
    -- ** Circuit Breaker (re-exported from tower-hs)
  , CircuitBreakerConfig(..)
  , CircuitBreakerState(..)
  , CircuitBreaker
  , newCircuitBreaker
  , withCircuitBreaker
  , getCircuitBreakerState
    -- ** Tracing (OpenTelemetry)
  , withTracing
  , withTracingTracer
    -- ** Set Header
  , withHeader
  , withHeaders
  , withBearerAuth
  , withUserAgent
    -- ** Request ID
  , withRequestId
  , withRequestIdHeader
    -- ** Follow Redirects
  , withFollowRedirects
    -- ** Filter (re-exported from tower-hs)
  , withFilter
  , withNoRetryOn
    -- ** Hedge (re-exported from tower-hs)
  , withHedge
    -- ** Response Validation
  , withValidateStatus
  , withValidateHeader
  , withValidateContentType
    -- ** Test Doubles
  , withMock
  , withMockMap
  , withRecorder
  ) where

import Tower.Service
import Tower.Error
import Tower.Middleware.Retry
import Tower.Middleware.Timeout
import Tower.Middleware.CircuitBreaker
import Tower.Middleware.Filter
import Tower.Middleware.Hedge
import Network.HTTP.Tower.Client
import Network.HTTP.Tower.Middleware.Logging
import Network.HTTP.Tower.Middleware.Tracing
import Network.HTTP.Tower.Middleware.SetHeader
import Network.HTTP.Tower.Middleware.RequestId
import Network.HTTP.Tower.Middleware.FollowRedirect
import Network.HTTP.Tower.Middleware.Validate
import Network.HTTP.Tower.Middleware.TestDouble
