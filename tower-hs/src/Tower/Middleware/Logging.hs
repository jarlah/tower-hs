-- |
-- Module      : Tower.Middleware.Logging
-- Description : Generic request/response logging middleware
-- License     : MIT
--
-- Times each service call and delegates formatting to a user-provided function.
--
-- @
-- let formatter req result duration = case result of
--       Right _  -> "OK (" <> pack (show (round (duration * 1000))) <> "ms)"
--       Left err -> "ERR: " <> displayError err
-- 'withLogging' formatter putStrLn
-- @
module Tower.Middleware.Logging
  ( withLogging
  ) where

import Data.Text (Text)
import Data.Time.Clock (getCurrentTime, diffUTCTime)

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError)

-- | Generic logging middleware: times the service call and passes
-- the request, result, and duration (in seconds) to a formatter.
--
-- The formatter produces a 'Text' message which is passed to the logger.
-- This middleware does not alter the result.
withLogging
  :: (req -> Either ServiceError res -> Double -> Text)  -- ^ Formatter
  -> (Text -> IO ())                                      -- ^ Logger
  -> Middleware req res
withLogging formatter logger inner = Service $ \req -> do
  start <- getCurrentTime
  result <- runService inner req
  end <- getCurrentTime
  let durationSec = realToFrac (diffUTCTime end start) :: Double
  logger (formatter req result durationSec)
  pure result
