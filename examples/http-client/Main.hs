{-# LANGUAGE OverloadedStrings #-}

-- | Example: HTTP client with a full tower-hs middleware stack.
--
-- Demonstrates composing generic tower-hs middleware (retry, timeout,
-- circuit breaker) with HTTP-specific middleware (headers, validation,
-- logging, tracing) using the |> operator.
--
-- Run with: stack run example-http-client
module Main where

import qualified Data.Text.IO as T
import qualified Network.HTTP.Client as HTTP

import Network.HTTP.Tower

main :: IO ()
main = do
  putStrLn "=== tower-hs HTTP client example ==="

  -- Create client and circuit breaker (shared across requests)
  client <- newClient
  breaker <- newCircuitBreaker

  let config = CircuitBreakerConfig
        { cbFailureThreshold = 5
        , cbCooldownPeriod   = 30
        }
      configured = client
        -- Generic tower-hs middleware
        |> withRetry (exponentialBackoff 3 0.5 2.0)
        |> withTimeout 10000
        |> withCircuitBreaker config breaker
        -- HTTP-specific middleware
        |> withUserAgent "tower-hs-example/0.1"
        |> withRequestId
        |> withValidateStatus (\c -> c >= 200 && c < 300)
        |> withLogging T.putStrLn
        |> withTracing

  -- Make a request
  req <- HTTP.parseRequest "https://httpbin.org/get"
  result <- runRequest configured req

  case result of
    Left err   -> putStrLn $ "Failed: " <> show err
    Right resp -> do
      putStrLn $ "Status: " <> show (HTTP.responseStatus resp)
      putStrLn "Success!"

  -- Check circuit breaker state
  state <- getCircuitBreakerState breaker
  putStrLn $ "Circuit breaker: " <> show state
