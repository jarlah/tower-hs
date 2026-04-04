{-# LANGUAGE NumericUnderscores #-}

module Network.HTTP.Tower.Middleware.Retry
  ( BackoffStrategy(..)
  , constantBackoff
  , exponentialBackoff
  , withRetry
  , computeDelay
  ) where

import Control.Concurrent (threadDelay)
import Data.Time.Clock (NominalDiffTime)

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Strategy for computing delay between retries.
data BackoffStrategy
  = ConstantBackoff
      { backoffMaxRetries :: !Int
      , backoffDelay      :: !NominalDiffTime  -- ^ delay between retries
      }
  | ExponentialBackoff
      { backoffMaxRetries :: !Int
      , backoffBaseDelay  :: !NominalDiffTime  -- ^ initial delay
      , backoffMultiplier :: !Double            -- ^ multiplier per attempt
      }
  deriving (Show, Eq)

-- | Constant backoff: same delay between every retry.
constantBackoff :: Int -> NominalDiffTime -> BackoffStrategy
constantBackoff = ConstantBackoff

-- | Exponential backoff: delay grows by multiplier each attempt.
exponentialBackoff :: Int -> NominalDiffTime -> Double -> BackoffStrategy
exponentialBackoff = ExponentialBackoff

-- | Compute the delay for a given attempt number (0-indexed).
computeDelay :: BackoffStrategy -> Int -> NominalDiffTime
computeDelay (ConstantBackoff _ d) _ = d
computeDelay (ExponentialBackoff _ base mult) attempt =
  base * realToFrac (mult ^^ attempt)

-- | Retry middleware: retries failed requests according to the backoff strategy.
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
