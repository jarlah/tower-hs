{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Network.HTTP.Tower.Middleware.SetHeader
-- Description : Add headers to every request
-- License     : MIT
--
-- @
-- client '|>' 'withBearerAuth' \"my-token\"
-- client '|>' 'withUserAgent' \"my-app\/1.0\"
-- client '|>' 'withHeader' \"X-Custom\" \"value\"
-- @
module Network.HTTP.Tower.Middleware.SetHeader
  ( withHeader
  , withHeaders
  , withBearerAuth
  , withUserAgent
  ) where

import Data.ByteString (ByteString)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Header as HTTP

import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service (Middleware)
import Tower.Middleware.Transform (withMapRequestPure)

-- | Add a single header to every request.
withHeader :: HTTP.HeaderName -> ByteString -> Middleware HTTP.Request HttpResponse
withHeader name value = withMapRequestPure $ \req ->
  req { HTTP.requestHeaders = (name, value) : HTTP.requestHeaders req }

-- | Add multiple headers to every request.
withHeaders :: [HTTP.Header] -> Middleware HTTP.Request HttpResponse
withHeaders hdrs = withMapRequestPure $ \req ->
  req { HTTP.requestHeaders = hdrs ++ HTTP.requestHeaders req }

-- | Add a @Authorization: Bearer \<token\>@ header.
withBearerAuth :: ByteString -> Middleware HTTP.Request HttpResponse
withBearerAuth token = withHeader "Authorization" ("Bearer " <> token)

-- | Set the @User-Agent@ header.
withUserAgent :: ByteString -> Middleware HTTP.Request HttpResponse
withUserAgent = withHeader "User-Agent"
