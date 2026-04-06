-- |
-- Module      : Tower.Middleware.Transform
-- Description : Generic request transformation middleware
-- License     : MIT
--
-- Transform the request before passing it to the inner service.
--
-- @
-- 'withMapRequest' (\\req -> addCorrelationId req)
-- 'withMapRequestPure' (\\req -> req { field = newValue })
-- @
module Tower.Middleware.Transform
  ( withMapRequest
  , withMapRequestPure
  ) where

import Tower.Service (Service(..), Middleware)

-- | Transform the request using an effectful function before passing
-- it to the inner service. Useful for adding generated IDs, timestamps, etc.
withMapRequest :: (req -> IO req) -> Middleware req res
withMapRequest f inner = Service $ \req -> do
  req' <- f req
  runService inner req'

-- | Transform the request using a pure function before passing
-- it to the inner service. Useful for adding static headers, tags, etc.
withMapRequestPure :: (req -> req) -> Middleware req res
withMapRequestPure f inner = Service $ \req ->
  runService inner (f req)
