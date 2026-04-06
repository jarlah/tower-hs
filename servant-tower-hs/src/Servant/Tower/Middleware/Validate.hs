{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Servant.Tower.Middleware.Validate
-- Description : Response validation middleware for servant
-- License     : MIT
module Servant.Tower.Middleware.Validate
  ( withValidateStatus
  , withValidateHeader
  , withValidateContentType
  ) where

import Data.ByteString (ByteString, isInfixOf)
import Data.Text (pack)
import qualified Data.Foldable as F
import Network.HTTP.Types.Header (HeaderName)
import Network.HTTP.Types.Status (statusCode)

import Servant.Client.Core (Request, Response, responseStatusCode, responseHeaders)
import Tower.Service (Middleware)
import Tower.Middleware.Validate (withValidate)

-- | Validate the response status code. Returns a 'CustomError' if the
-- predicate returns 'False'.
withValidateStatus :: (Int -> Bool) -> Middleware Request Response
withValidateStatus isValid = withValidate $ \resp ->
  let code = statusCode (responseStatusCode resp)
  in if isValid code
      then Nothing
      else Just ("Unexpected status code: " <> pack (show code))

-- | Validate that a specific response header is present.
withValidateHeader :: HeaderName -> Middleware Request Response
withValidateHeader headerName = withValidate $ \resp ->
  if F.any (\(n, _) -> n == headerName) (responseHeaders resp)
    then Nothing
    else Just ("Missing required header: " <> pack (show headerName))

-- | Validate the @Content-Type@ header contains the expected value.
--
-- Uses substring matching, so @\"application\/json\"@ matches
-- @\"application\/json; charset=utf-8\"@.
withValidateContentType :: ByteString -> Middleware Request Response
withValidateContentType expected = withValidate $ \resp ->
  let ct = F.find (\(n, _) -> n == "Content-Type") (responseHeaders resp)
  in case ct of
    Just (_, v) | expected `isInfixOf` v -> Nothing
    Just (_, v) -> Just ("Unexpected Content-Type: " <> pack (show v))
    Nothing -> Just "Missing Content-Type header"
