-- |
-- Module      : Tower
-- Description : Composable service middleware for Haskell
-- License     : MIT
--
-- Inspired by Rust's <https://docs.rs/tower/latest/tower/ Tower> crate.
-- Build composable middleware stacks for any service type.
--
-- @
-- import Tower
--
-- -- Define a service
-- let svc = 'Service' $ \\req -> pure (Right (process req))
--
-- -- Compose middleware
-- let robust = 'withRetry' ('constantBackoff' 3 1.0)
--            . 'withTimeout' 5000
--            $ svc
-- @
--
-- All errors are returned as @'Either' 'ServiceError' response@ — no exceptions
-- escape the middleware stack.
module Tower
  ( -- * Core types
    Service(..)
  , Middleware
  , mapService
  , composeMiddleware
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
    -- ** Circuit Breaker
  , CircuitBreakerConfig(..)
  , CircuitBreakerState(..)
  , CircuitBreaker
  , newCircuitBreaker
  , withCircuitBreaker
  , getCircuitBreakerState
    -- ** Filter
  , withFilter
  , withNoRetryOn
    -- ** Hedge
  , withHedge
    -- ** Logging
  , withLogging
    -- ** Tracing (OpenTelemetry)
  , TracingConfig(..)
  , defaultTracingConfig
  , withTracingConfig
  , withTracingGlobal
    -- ** Request Transform
  , withMapRequest
  , withMapRequestPure
    -- ** Response Validation
  , Tower.Middleware.Validate.withValidate
    -- ** Test Doubles
  , withMock
  , withRecorder
  ) where

import Tower.Service
import Tower.Error
import Tower.Middleware.Retry
import Tower.Middleware.Timeout
import Tower.Middleware.CircuitBreaker
import Tower.Middleware.Filter
import Tower.Middleware.Hedge
import Tower.Middleware.Logging
import Tower.Middleware.Tracing
import Tower.Middleware.Transform
import Tower.Middleware.Validate
import Tower.Middleware.TestDouble
