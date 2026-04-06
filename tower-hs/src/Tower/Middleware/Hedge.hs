{-# LANGUAGE NumericUnderscores #-}

-- |
-- Module      : Tower.Middleware.Hedge
-- Description : Speculative retry via async race
-- License     : MIT
--
-- If the primary request is slow, fire a second speculative request after
-- a delay and return whichever finishes first.
--
-- @
-- 'withHedge' 200  -- hedge after 200ms
-- @
--
-- __Only use for idempotent requests__ since the request may
-- be sent twice.
module Tower.Middleware.Hedge
  ( withHedge
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race)

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError)

-- | Hedging middleware: if the primary request doesn't complete within
-- @delayMs@ milliseconds, fire a second request and return whichever
-- finishes first.
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
