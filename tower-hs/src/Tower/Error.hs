{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Tower.Error
-- Description : Error types for the middleware stack
-- License     : MIT
--
-- All middleware returns @Either 'ServiceError' response@ — no exceptions
-- escape the middleware stack.
module Tower.Error
  ( ServiceError(..)
  , displayError
  ) where

import Control.Exception (SomeException)
import Data.Text (Text, pack)

-- | Errors that can occur in a middleware stack.
--
-- All middleware returns @Either ServiceError Response@ — no exceptions escape.
data ServiceError
  = TransportError SomeException
    -- ^ An underlying transport exception (connection refused, DNS failure, etc.)
  | TimeoutError
    -- ^ The request exceeded the configured timeout.
  | RetryExhausted Int ServiceError
    -- ^ All retries failed. Contains the number of attempts and the last error.
  | CircuitBreakerOpen
    -- ^ The circuit breaker is open — requests are being rejected.
  | CustomError Text
    -- ^ A custom error from middleware (e.g., validation failure, too many redirects).
  deriving (Show)

-- | Render a 'ServiceError' as human-readable 'Text'.
displayError :: ServiceError -> Text
displayError (TransportError e)    = pack $ "Transport error: " <> show e
displayError TimeoutError          = "Request timed out"
displayError (RetryExhausted n err) = "Retry exhausted after " <> pack (show n) <> " attempts: " <> displayError err
displayError CircuitBreakerOpen    = "Circuit breaker is open"
displayError (CustomError t)       = t
