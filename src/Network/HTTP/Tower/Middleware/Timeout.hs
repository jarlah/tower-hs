-- |
-- Module      : Network.HTTP.Tower.Middleware.Timeout
-- Description : Timeout middleware
-- License     : MIT
--
-- Fails with 'TimeoutError' if the inner service doesn't respond within
-- the specified number of milliseconds.
--
-- @
-- client '|>' 'withTimeout' 5000  -- 5 second timeout
-- @
module Network.HTTP.Tower.Middleware.Timeout
  ( withTimeout
  ) where

import qualified System.Timeout as Sys

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Timeout middleware: fails with 'TimeoutError' if the request takes
-- longer than the specified number of milliseconds.
withTimeout :: Int -> Middleware req res
withTimeout ms inner = Service $ \req -> do
  let micros = ms * 1000
  result <- Sys.timeout micros (runService inner req)
  pure $ case result of
    Nothing        -> Left TimeoutError
    Just innerRes  -> innerRes
