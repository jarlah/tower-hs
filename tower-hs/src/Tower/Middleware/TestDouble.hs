-- |
-- Module      : Tower.Middleware.TestDouble
-- Description : Mock services and request recording for testing
-- License     : MIT
--
-- @
-- -- Replace the service entirely
-- 'withMock' (\\req -> pure (Right fakeResponse))
--
-- -- Record requests for assertions
-- recorder <- newIORef []
-- 'withRecorder' recorder
-- @
module Tower.Middleware.TestDouble
  ( withMock
  , withRecorder
  ) where

import Data.IORef

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError)

-- | Replace the inner service entirely with a mock function.
-- The inner service is never called.
withMock
  :: (req -> IO (Either ServiceError res))
  -> Middleware req res
withMock handler _inner = Service handler

-- | Record all requests that pass through, then forward to the inner service.
-- The recorder stores requests in reverse order (most recent first).
--
-- @
-- recorder <- newIORef []
-- let svc = 'withRecorder' recorder innerService
-- @
withRecorder :: IORef [req] -> Middleware req res
withRecorder ref inner = Service $ \req -> do
  modifyIORef' ref (req :)
  runService inner req
