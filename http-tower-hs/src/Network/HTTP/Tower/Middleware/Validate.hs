{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Network.HTTP.Tower.Middleware.Validate
-- Description : HTTP response validation middleware
-- License     : MIT
--
-- Reject responses that don't meet expectations:
--
-- @
-- client '|>' 'withValidateStatus' (\\c -> c >= 200 && c < 300)
-- client '|>' 'withValidateContentType' \"application\/json\"
-- client '|>' 'withValidateHeader' \"X-Request-ID\"
-- @
module Network.HTTP.Tower.Middleware.Validate
  ( withValidateStatus
  , withValidateHeader
  , withValidateContentType
  ) where

import Data.ByteString (ByteString, isInfixOf)
import Data.Text (pack)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Header as HTTP
import qualified Network.HTTP.Types.Status as HTTP

import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service (Middleware)
import Tower.Middleware.Validate (withValidate)

-- | Validate the response status code. Returns a 'CustomError' if the
-- predicate returns 'False'.
withValidateStatus :: (Int -> Bool) -> Middleware HTTP.Request HttpResponse
withValidateStatus isValid = withValidate $ \resp ->
  let code = HTTP.statusCode (HTTP.responseStatus resp)
  in if isValid code
      then Nothing
      else Just ("Unexpected status code: " <> pack (show code))

-- | Validate that a specific response header is present.
withValidateHeader :: HTTP.HeaderName -> Middleware HTTP.Request HttpResponse
withValidateHeader headerName = withValidate $ \resp ->
  case lookup headerName (HTTP.responseHeaders resp) of
    Just _  -> Nothing
    Nothing -> Just ("Missing required header: " <> pack (show headerName))

-- | Validate the @Content-Type@ header contains the expected value.
--
-- Uses substring matching, so @\"application\/json\"@ matches
-- @\"application\/json; charset=utf-8\"@.
withValidateContentType :: ByteString -> Middleware HTTP.Request HttpResponse
withValidateContentType expected = withValidate $ \resp ->
  case lookup "Content-Type" (HTTP.responseHeaders resp) of
    Just ct | expected `isInfixOf` ct -> Nothing
    Just ct -> Just ("Unexpected Content-Type: " <> pack (show ct))
    Nothing -> Just "Missing Content-Type header"
