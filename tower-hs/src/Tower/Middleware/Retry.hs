{-# LANGUAGE NumericUnderscores #-}

-- |
-- Module      : Tower.Middleware.Retry
-- Description : Retry middleware with configurable backoff
-- License     : MIT
--
-- Retries failed requests with constant or exponential backoff.
--
-- @
-- 'withRetry' ('constantBackoff' 3 1.0)
-- 'withRetry' ('exponentialBackoff' 5 0.5 2.0)
-- @
module Tower.Middleware.Retry
  ( BackoffStrategy(..)
  , constantBackoff
  , exponentialBackoff
  , withRetry
  , computeDelay
  ) where

import Control.Concurrent (threadDelay)
import Data.Time.Clock (NominalDiffTime)

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError(..))

-- | Strategy for computing delay between retries.
data BackoffStrategy
  = ConstantBackoff
      { backoffMaxRetries :: !Int
        -- ^ Maximum number of retries.
      , backoffDelay      :: !NominalDiffTime
        -- ^ Fixed delay between retries.
      }
  | ExponentialBackoff
      { backoffMaxRetries :: !Int
        -- ^ Maximum number of retries.
      , backoffBaseDelay  :: !NominalDiffTime
        -- ^ Initial delay before first retry.
      , backoffMultiplier :: !Double
        -- ^ Multiplier applied to delay after each attempt.
      }
  deriving (Show, Eq)

-- | Constant backoff: same delay between every retry.
--
-- @'constantBackoff' 3 1.0@ — retry up to 3 times, 1 second apart.
constantBackoff :: Int -> NominalDiffTime -> BackoffStrategy
constantBackoff = ConstantBackoff

-- | Exponential backoff: delay grows by multiplier each attempt.
--
-- @'exponentialBackoff' 5 0.5 2.0@ — retry up to 5 times, starting at 500ms, doubling each time.
exponentialBackoff :: Int -> NominalDiffTime -> Double -> BackoffStrategy
exponentialBackoff = ExponentialBackoff

-- | Compute the delay for a given attempt number (0-indexed).
computeDelay :: BackoffStrategy -> Int -> NominalDiffTime
computeDelay (ConstantBackoff _ d) _ = d
computeDelay (ExponentialBackoff _ base mult) attempt =
  base * realToFrac (mult ^^ attempt)

-- | Retry middleware: retries failed requests according to the backoff strategy.
--
-- On failure, waits for the computed delay, then retries. After all retries
-- are exhausted, returns 'RetryExhausted' with the attempt count and last error.
withRetry :: BackoffStrategy -> Middleware req res
withRetry strategy inner = Service $ \req ->
  go req 0
  where
    maxRetries = backoffMaxRetries strategy

    go req attempt = do
      result <- runService inner req
      case result of
        Right resp -> pure (Right resp)
        Left err
          | attempt >= maxRetries ->
              pure (Left (RetryExhausted attempt err))
          | otherwise -> do
              let delaySeconds = computeDelay strategy attempt
                  delayMicros = round (delaySeconds * 1_000_000) :: Int
              threadDelay delayMicros
              go req (attempt + 1)
