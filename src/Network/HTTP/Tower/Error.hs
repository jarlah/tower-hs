{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Error
  ( ServiceError(..)
  , displayError
  ) where

import Control.Exception (SomeException)
import Data.Text (Text, pack)

-- | Errors that can occur in a middleware stack.
-- All middleware returns 'Either ServiceError Response' — no exceptions escape.
data ServiceError
  = HttpError SomeException
  | TimeoutError
  | RetryExhausted Int ServiceError  -- ^ retries attempted, last error
  | CircuitBreakerOpen
  | CustomError Text
  deriving (Show)

displayError :: ServiceError -> Text
displayError (HttpError e)          = pack $ "HTTP error: " <> show e
displayError TimeoutError           = "Request timed out"
displayError (RetryExhausted n err) = "Retry exhausted after " <> pack (show n) <> " attempts: " <> displayError err
displayError CircuitBreakerOpen     = "Circuit breaker is open"
displayError (CustomError t)        = t
