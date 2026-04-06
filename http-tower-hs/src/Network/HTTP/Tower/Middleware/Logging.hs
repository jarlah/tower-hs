{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Network.HTTP.Tower.Middleware.Logging
-- Description : HTTP request/response logging middleware
-- License     : MIT
--
-- Logs HTTP method, host, status code, and duration for each request.
--
-- @
-- client '|>' 'withLogging' (\\msg -> Data.Text.IO.putStrLn msg)
-- @
module Network.HTTP.Tower.Middleware.Logging
  ( withLogging
  , withLoggingCustom
  ) where

import Data.Text (Text, pack)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Status as HTTP

import qualified Tower.Middleware.Logging as Generic
import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service (Middleware)
import Tower.Error (ServiceError, displayError)

-- | Logging middleware using a simple @Text -> IO ()@ logger.
-- Logs method, URL, status code, and duration for each request.
withLogging :: (Text -> IO ()) -> Middleware HTTP.Request HttpResponse
withLogging = Generic.withLogging httpFormatter

-- | Logging middleware with a custom formatter.
--
-- The formatter receives the request, the result, and the duration in seconds.
withLoggingCustom
  :: (HTTP.Request -> Either ServiceError HttpResponse -> Double -> Text)
  -> (Text -> IO ())
  -> Middleware HTTP.Request HttpResponse
withLoggingCustom = Generic.withLogging

httpFormatter :: HTTP.Request -> Either ServiceError HttpResponse -> Double -> Text
httpFormatter req result duration =
  let method = pack $ show (HTTP.method req)
      url    = pack $ show (HTTP.host req) <> show (HTTP.path req)
      status = case result of
        Right resp -> pack $ show (HTTP.statusCode (HTTP.responseStatus resp))
        Left err   -> "ERR: " <> displayError err
      dur = pack $ show (round (duration * 1000) :: Int) <> "ms"
  in method <> " " <> url <> " -> " <> status <> " (" <> dur <> ")"
