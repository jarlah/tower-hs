{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.Filter
  ( withFilter
  , withNoRetryOn
  ) where

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Only pass requests through that match a predicate.
-- Requests that don't match are rejected with a CustomError.
withFilter :: (req -> Bool) -> Middleware req res
withFilter predicate inner = Service $ \req ->
  if predicate req
    then runService inner req
    else pure (Left (CustomError "Request filtered out"))

-- | Don't retry responses that match a predicate.
-- Place between retry and the base service.
withNoRetryOn :: (res -> Bool) -> Middleware req res
withNoRetryOn shouldNotRetry inner = Service $ \req -> do
  result <- runService inner req
  case result of
    Right resp
      | shouldNotRetry resp -> pure (Right resp)
    _ -> pure result
