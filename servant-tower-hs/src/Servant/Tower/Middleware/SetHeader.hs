{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Servant.Tower.Middleware.SetHeader
-- Description : Add headers to every servant request
-- License     : MIT
module Servant.Tower.Middleware.SetHeader
  ( withHeader
  , withHeaders
  , withBearerAuth
  , withUserAgent
  ) where

import Data.ByteString (ByteString)
import qualified Data.Sequence as Seq
import Network.HTTP.Types.Header (HeaderName)

import Servant.Client.Core (Request, Response, requestHeaders)
import Tower.Service (Middleware)
import Tower.Middleware.Transform (withMapRequestPure)

-- | Add a single header to every request.
withHeader :: HeaderName -> ByteString -> Middleware Request Response
withHeader name value = withMapRequestPure $ \req ->
  req { requestHeaders = requestHeaders req Seq.|> (name, value) }

-- | Add multiple headers to every request.
withHeaders :: [(HeaderName, ByteString)] -> Middleware Request Response
withHeaders hdrs = withMapRequestPure $ \req ->
  req { requestHeaders = requestHeaders req <> Seq.fromList hdrs }

-- | Add a @Authorization: Bearer \<token\>@ header.
withBearerAuth :: ByteString -> Middleware Request Response
withBearerAuth token = withHeader "Authorization" ("Bearer " <> token)

-- | Set the @User-Agent@ header.
withUserAgent :: ByteString -> Middleware Request Response
withUserAgent = withHeader "User-Agent"
