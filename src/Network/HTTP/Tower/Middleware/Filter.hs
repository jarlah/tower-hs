{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Network.HTTP.Tower.Middleware.Filter
-- Description : Predicate-based request and response filtering
-- License     : MIT
--
-- @
-- -- Only allow GET requests
-- client '|>' 'withFilter' (\\req -> HTTP.method req == \"GET\")
--
-- -- Don't retry 4xx responses
-- client '|>' 'withNoRetryOn' (\\resp -> statusCode (responseStatus resp) < 500)
-- @
module Network.HTTP.Tower.Middleware.Filter
  ( withFilter
  , withNoRetryOn
  ) where

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Only pass requests through that match a predicate.
-- Requests that don't match are rejected with @'CustomError' \"Request filtered out\"@.
withFilter :: (req -> Bool) -> Middleware req res
withFilter predicate inner = Service $ \req ->
  if predicate req
    then runService inner req
    else pure (Left (CustomError "Request filtered out"))

-- | Don't retry responses that match a predicate.
-- Pass-through middleware — place between retry and the base service.
--
-- Responses matching the predicate are returned as-is (success), so
-- the retry middleware above won't retry them.
withNoRetryOn :: (res -> Bool) -> Middleware req res
withNoRetryOn shouldNotRetry inner = Service $ \req -> do
  result <- runService inner req
  case result of
    Right resp
      | shouldNotRetry resp -> pure (Right resp)
    _ -> pure result
