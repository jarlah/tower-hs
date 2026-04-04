{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.Logging
  ( withLogging
  , withLoggingCustom
  ) where

import Data.Text (Text, pack)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Status as HTTP

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError, displayError)

-- | Logging middleware using a simple @Text -> IO ()@ logger.
-- Logs method, URL, status code, and duration for each request.
withLogging :: (Text -> IO ()) -> Middleware HTTP.Request HttpResponse
withLogging = withLoggingCustom formatDefault

-- | Logging middleware with a custom formatter.
withLoggingCustom
  :: (HTTP.Request -> Either ServiceError HttpResponse -> Double -> Text)
  -> (Text -> IO ())
  -> Middleware HTTP.Request HttpResponse
withLoggingCustom formatter logger inner = Service $ \req -> do
  start <- getCurrentTime
  result <- runService inner req
  end <- getCurrentTime
  let durationSec = realToFrac (diffUTCTime end start) :: Double
  logger (formatter req result durationSec)
  pure result

formatDefault :: HTTP.Request -> Either ServiceError HttpResponse -> Double -> Text
formatDefault req result duration =
  let method = pack $ show (HTTP.method req)
      url    = pack $ show (HTTP.host req) <> show (HTTP.path req)
      status = case result of
        Right resp -> pack $ show (HTTP.statusCode (HTTP.responseStatus resp))
        Left err   -> "ERR: " <> displayError err
      dur = pack $ show (round (duration * 1000) :: Int) <> "ms"
  in method <> " " <> url <> " -> " <> status <> " (" <> dur <> ")"
