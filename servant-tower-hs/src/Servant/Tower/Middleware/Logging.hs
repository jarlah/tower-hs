{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Servant.Tower.Middleware.Logging
-- Description : Request/response logging for servant requests
-- License     : MIT
module Servant.Tower.Middleware.Logging
  ( withLogging
  , withLoggingCustom
  ) where

import Data.Text (Text, pack)
import Data.Text.Encoding (decodeUtf8)
import Network.HTTP.Types.Status (statusCode)

import qualified Tower.Middleware.Logging as Generic
import Servant.Client.Core (Request, Response, requestMethod, responseStatusCode)
import Tower.Service (Middleware)
import Tower.Error (ServiceError, displayError)

-- | Logging middleware with a default servant-aware formatter.
-- Logs method, status code, and duration.
withLogging :: (Text -> IO ()) -> Middleware Request Response
withLogging = Generic.withLogging servantFormatter

-- | Logging middleware with a custom formatter.
withLoggingCustom
  :: (Request -> Either ServiceError Response -> Double -> Text)
  -> (Text -> IO ())
  -> Middleware Request Response
withLoggingCustom = Generic.withLogging

servantFormatter :: Request -> Either ServiceError Response -> Double -> Text
servantFormatter req result duration =
  let method = decodeUtf8 (requestMethod req)
      status = case result of
        Right resp -> pack $ show (statusCode (responseStatusCode resp))
        Left err   -> "ERR: " <> displayError err
      dur = pack $ show (round (duration * 1000) :: Int) <> "ms"
  in method <> " -> " <> status <> " (" <> dur <> ")"
