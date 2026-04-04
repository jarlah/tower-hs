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
    -- ** Filter
  , withFilter
  , withNoRetryOn

    -- ** Hedge
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

import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Client
import Network.HTTP.Tower.Error
import Network.HTTP.Tower.Middleware.Retry
import Network.HTTP.Tower.Middleware.Timeout
import Network.HTTP.Tower.Middleware.Logging
import Network.HTTP.Tower.Middleware.CircuitBreaker
import Network.HTTP.Tower.Middleware.Tracing
import Network.HTTP.Tower.Middleware.SetHeader
import Network.HTTP.Tower.Middleware.RequestId
import Network.HTTP.Tower.Middleware.FollowRedirect
import Network.HTTP.Tower.Middleware.Filter
import Network.HTTP.Tower.Middleware.Hedge
import Network.HTTP.Tower.Middleware.Validate
import Network.HTTP.Tower.Middleware.TestDouble
