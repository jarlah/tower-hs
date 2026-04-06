-- |
-- Module      : Tower.Middleware.Validate
-- Description : Generic response validation middleware
-- License     : MIT
--
-- Reject responses that fail a check.
--
-- @
-- 'withValidate' (\\res -> if isValid res then Nothing else Just "invalid")
-- @
module Tower.Middleware.Validate
  ( withValidate
  ) where

import Data.Text (Text)

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError(..))

-- | Reject responses that fail a validation check.
--
-- The check function inspects the response and returns 'Nothing' if valid,
-- or @'Just' errorMessage@ to reject with a 'CustomError'.
withValidate :: (res -> Maybe Text) -> Middleware req res
withValidate check inner = Service $ \req -> do
  result <- runService inner req
  case result of
    Right res -> case check res of
      Nothing  -> pure (Right res)
      Just err -> pure (Left (CustomError err))
    Left err -> pure (Left err)
