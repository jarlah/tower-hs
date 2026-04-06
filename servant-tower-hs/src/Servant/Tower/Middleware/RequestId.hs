{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Servant.Tower.Middleware.RequestId
-- Description : Generate unique request IDs for servant requests
-- License     : MIT
module Servant.Tower.Middleware.RequestId
  ( withRequestId
  , withRequestIdHeader
  ) where

import Data.ByteString.Char8 (pack)
import Data.UUID (toString)
import Data.UUID.V4 (nextRandom)
import qualified Data.Sequence as Seq
import Network.HTTP.Types.Header (HeaderName)

import Servant.Client.Core (Request, Response, requestHeaders)
import Tower.Service (Middleware)
import Tower.Middleware.Transform (withMapRequest)

-- | Add a unique @X-Request-ID@ header with a UUID v4 to every request.
withRequestId :: Middleware Request Response
withRequestId = withRequestIdHeader "X-Request-ID"

-- | Add a unique request ID using a custom header name.
withRequestIdHeader :: HeaderName -> Middleware Request Response
withRequestIdHeader headerName = withMapRequest $ \req -> do
  uuid <- nextRandom
  let reqId = pack (toString uuid)
  pure req { requestHeaders = requestHeaders req Seq.|> (headerName, reqId) }
