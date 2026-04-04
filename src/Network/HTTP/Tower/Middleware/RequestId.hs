{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.RequestId
  ( withRequestId
  , withRequestIdHeader
  ) where

import Data.ByteString.Char8 (pack)
import Data.UUID (toString)
import Data.UUID.V4 (nextRandom)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Header as HTTP

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core (Service(..), Middleware)

-- | Add a unique request ID header (X-Request-ID) to every request.
-- Generates a UUID v4 for each request.
withRequestId :: Middleware HTTP.Request HttpResponse
withRequestId = withRequestIdHeader "X-Request-ID"

-- | Add a unique request ID using a custom header name.
withRequestIdHeader :: HTTP.HeaderName -> Middleware HTTP.Request HttpResponse
withRequestIdHeader headerName inner = Service $ \req -> do
  uuid <- nextRandom
  let reqId = pack (toString uuid)
      req' = req { HTTP.requestHeaders = (headerName, reqId) : HTTP.requestHeaders req }
  runService inner req'
