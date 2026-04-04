{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.FollowRedirect
  ( withFollowRedirects
  ) where

import Data.ByteString.Char8 (unpack)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Status as HTTP

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Follow HTTP 3xx redirects up to a maximum number of hops.
-- Handles 301, 302, 303, 307, and 308 by reading the Location header.
-- 303 responses change the method to GET (per HTTP spec).
withFollowRedirects :: Int -> Middleware HTTP.Request HttpResponse
withFollowRedirects maxRedirects inner = Service $ \req ->
  go req 0
  where
    go req hops
      | hops >= maxRedirects = pure (Left (CustomError "Too many redirects"))
      | otherwise = do
          result <- runService inner req
          case result of
            Left err -> pure (Left err)
            Right resp
              | isRedirect (HTTP.responseStatus resp) ->
                  case lookup "Location" (HTTP.responseHeaders resp) of
                    Nothing -> pure (Right resp)
                    Just loc -> do
                      newReq <- HTTP.parseRequest (unpack loc)
                      let req' = if HTTP.statusCode (HTTP.responseStatus resp) == 303
                            then newReq { HTTP.method = "GET", HTTP.requestBody = "" }
                            else newReq { HTTP.method = HTTP.method req }
                      go req' (hops + 1)
              | otherwise -> pure (Right resp)

    isRedirect s = HTTP.statusCode s `elem` [301, 302, 303, 307, 308]
