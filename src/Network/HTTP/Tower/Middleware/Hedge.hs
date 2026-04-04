{-# LANGUAGE NumericUnderscores #-}

module Network.HTTP.Tower.Middleware.Hedge
  ( withHedge
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race)

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError)

-- | Hedging middleware: if the first request doesn't complete within the
-- given delay (in milliseconds), fire a second speculative request and
-- return whichever finishes first.
--
-- This is useful for latency-sensitive services where occasional slow
-- requests can be mitigated by racing a duplicate.
--
-- Note: only use this for idempotent requests since the request may be
-- sent twice.
withHedge :: Int -> Middleware req res
withHedge delayMs inner = Service $ \req -> do
  let primary = runService inner req
      hedged = do
        threadDelay (delayMs * 1_000)
        runService inner req
  result <- race primary hedged
  pure $ case result of
    Left res  -> res
    Right res -> res
