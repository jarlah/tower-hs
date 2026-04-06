{-# OPTIONS_GHC -fno-warn-orphans #-}

-- |
-- Module      : Tower.Error.Testing
-- Description : Eq instance for ServiceError (testing only)
-- License     : MIT
--
-- Provides an 'Eq' instance for 'ServiceError' using @show@-based comparison
-- for the 'TransportError' case. Import this module in test suites only.
module Tower.Error.Testing () where

import Tower.Error (ServiceError(..))

instance Eq ServiceError where
  TransportError a   == TransportError b   = show a == show b
  TimeoutError       == TimeoutError       = True
  RetryExhausted n e == RetryExhausted m f = n == m && e == f
  CircuitBreakerOpen == CircuitBreakerOpen = True
  CustomError a      == CustomError b      = a == b
  _                  == _                  = False
