{-# LANGUAGE OverloadedStrings #-}

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
import Network.HTTP.Tower.Core (Service(..), Middleware)

-- | Add a single header to every request.
withHeader :: HTTP.HeaderName -> ByteString -> Middleware HTTP.Request HttpResponse
withHeader name value inner = Service $ \req ->
  let req' = req { HTTP.requestHeaders = (name, value) : HTTP.requestHeaders req }
  in runService inner req'

-- | Add multiple headers to every request.
withHeaders :: [HTTP.Header] -> Middleware HTTP.Request HttpResponse
withHeaders hdrs inner = Service $ \req ->
  let req' = req { HTTP.requestHeaders = hdrs ++ HTTP.requestHeaders req }
  in runService inner req'

-- | Add a Bearer token authorization header.
withBearerAuth :: ByteString -> Middleware HTTP.Request HttpResponse
withBearerAuth token = withHeader "Authorization" ("Bearer " <> token)

-- | Set the User-Agent header.
withUserAgent :: ByteString -> Middleware HTTP.Request HttpResponse
withUserAgent = withHeader "User-Agent"
