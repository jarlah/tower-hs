-- |
-- Module      : Tower.Service
-- Description : Core Service and Middleware abstractions
-- License     : MIT
--
-- The fundamental building blocks for composable middleware stacks.
-- A 'Service' is a function from request to @IO (Either ServiceError response)@,
-- and 'Middleware' wraps a service to add behavior.
module Tower.Service
  ( Service(..)
  , Middleware
  , mapService
  , composeMiddleware
  ) where

import Tower.Error (ServiceError)

-- | A service transforms a request into an effectful response.
-- This is the fundamental building block — middleware wraps services.
--
-- @
-- let echoService = 'Service' $ \\req -> pure (Right req)
-- result <- 'runService' echoService "hello"
-- -- result == Right "hello"
-- @
newtype Service req res = Service
  { runService :: req -> IO (Either ServiceError res)
    -- ^ Execute the service with a request, returning either an error or a response.
  }

-- | Middleware wraps a service to add behavior (retry, timeout, logging, etc.)
--
-- A middleware is simply a function from 'Service' to 'Service':
--
-- @
-- type Middleware req res = Service req res -> Service req res
-- @
type Middleware req res = Service req res -> Service req res

-- | Transform the response of a service, leaving errors unchanged.
--
-- @
-- let svc = 'Service' $ \\_ -> pure (Right 10)
-- let doubled = 'mapService' (* 2) svc
-- result <- 'runService' doubled ()
-- -- result == Right 20
-- @
mapService :: (a -> b) -> Service req a -> Service req b
mapService f (Service run) = Service $ \req -> fmap (fmap f) (run req)

-- | Compose two middleware, applying the outer first, then the inner.
--
-- @'composeMiddleware' outer inner = outer . inner@
composeMiddleware :: Middleware req res -> Middleware req res -> Middleware req res
composeMiddleware outer inner = outer . inner
