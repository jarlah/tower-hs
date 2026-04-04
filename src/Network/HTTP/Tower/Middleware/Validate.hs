{-# LANGUAGE OverloadedStrings #-}

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
import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Validate the response status code. If the predicate returns False,
-- the response is converted to a CustomError.
--
-- @
-- -- Reject anything that's not 2xx
-- client |> withValidateStatus (\\code -> code >= 200 && code < 300)
-- @
withValidateStatus :: (Int -> Bool) -> Middleware HTTP.Request HttpResponse
withValidateStatus isValid inner = Service $ \req -> do
  result <- runService inner req
  case result of
    Right resp ->
      let code = HTTP.statusCode (HTTP.responseStatus resp)
      in if isValid code
          then pure (Right resp)
          else pure (Left (CustomError ("Unexpected status code: " <> pack (show code))))
    Left err -> pure (Left err)

-- | Validate that a specific response header is present.
withValidateHeader :: HTTP.HeaderName -> Middleware HTTP.Request HttpResponse
withValidateHeader headerName inner = Service $ \req -> do
  result <- runService inner req
  case result of
    Right resp ->
      case lookup headerName (HTTP.responseHeaders resp) of
        Just _  -> pure (Right resp)
        Nothing -> pure (Left (CustomError ("Missing required header: " <> pack (show headerName))))
    Left err -> pure (Left err)

-- | Validate the Content-Type header contains the expected value.
--
-- @
-- client |> withValidateContentType "application/json"
-- @
withValidateContentType :: ByteString -> Middleware HTTP.Request HttpResponse
withValidateContentType expected inner = Service $ \req -> do
  result <- runService inner req
  case result of
    Right resp ->
      case lookup "Content-Type" (HTTP.responseHeaders resp) of
        Just ct | expected `isInfixOf` ct -> pure (Right resp)
        Just ct -> pure (Left (CustomError ("Unexpected Content-Type: " <> pack (show ct))))
        Nothing -> pure (Left (CustomError "Missing Content-Type header"))
    Left err -> pure (Left err)
