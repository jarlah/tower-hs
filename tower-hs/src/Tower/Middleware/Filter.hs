{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Tower.Middleware.Filter
-- Description : Predicate-based request and response filtering
-- License     : MIT
--
-- @
-- -- Only allow certain requests
-- 'withFilter' predicate
--
-- -- Don't retry matching responses
-- 'withNoRetryOn' predicate
-- @
module Tower.Middleware.Filter
  ( withFilter
  , withNoRetryOn
  ) where

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError(..))

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
