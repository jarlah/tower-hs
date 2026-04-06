{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Example: Generic tower-hs middleware with Redis (non-HTTP use case).
--
-- Demonstrates that tower-hs middleware works with any service type —
-- not just HTTP. Here we wrap a Redis client with retry, timeout,
-- circuit breaker, validation, and logging.
--
-- Requires a running Redis instance on localhost:6379.
-- Run with: stack run example-generic-redis
module Main where

import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Database.Redis as Redis

import Tower

main :: IO ()
main = do
  putStrLn "=== tower-hs Generic Redis example ==="
  putStrLn "Connecting to Redis on localhost:6379..."

  conn <- Redis.checkedConnect Redis.defaultConnectInfo

  -- Wrap Redis operations as tower-hs Services
  let getSet :: Service (ByteString, ByteString) ByteString
      getSet = Service $ \(key, value) -> do
        result <- try $ Redis.runRedis conn $ do
          _ <- Redis.set key value
          Redis.get key
        pure $ case result of
          Left (err :: SomeException) -> Left (TransportError err)
          Right (Right (Just v))      -> Right v
          Right (Right Nothing)       -> Left (CustomError "key not found")
          Right (Left reply)          -> Left (CustomError (T.pack (show reply)))

  -- Build a robust service with full middleware stack
  breaker <- newCircuitBreaker
  let config = CircuitBreakerConfig
        { cbFailureThreshold = 5
        , cbCooldownPeriod   = 30
        }
      robust = withRetry (constantBackoff 3 0)
             . withTimeout 5000
             . withCircuitBreaker config breaker
             . withValidate (\v ->
                 if v == "" then Just "empty value" else Nothing)
             . withLogging
                 (\(key, _) result dur -> case result of
                   Right _ -> "Redis SET+GET " <> T.pack (show key)
                              <> " OK (" <> T.pack (show (round (dur * 1000) :: Int)) <> "ms)"
                   Left err -> "Redis ERR: " <> displayError err)
                 T.putStrLn
             $ getSet

  -- Use the service
  result <- runService robust ("greeting", "Hello from tower-hs!")
  case result of
    Left err -> putStrLn $ "Failed: " <> show err
    Right v  -> putStrLn $ "Got: " <> show v

  state <- getCircuitBreakerState breaker
  putStrLn $ "Circuit breaker: " <> show state
