{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

-- | Example: Servant client with a full tower-hs middleware stack.
--
-- Demonstrates composing generic tower-hs middleware (retry, timeout,
-- circuit breaker) with servant-specific middleware (headers, validation,
-- logging) via the withTowerMiddleware adapter.
--
-- Run with: stack run example-servant-client
module Main where

import Data.Aeson (Value)
import Data.Function ((&))
import Data.Proxy (Proxy(..))
import qualified Data.Text.IO as T
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Servant.API
import Servant.Client

import Servant.Tower.Adapter (withTowerMiddleware)
import qualified Servant.Tower.Middleware.Logging as STL
import qualified Servant.Tower.Middleware.SetHeader as STS
import qualified Servant.Tower.Middleware.Validate as STV
import Tower.Middleware.CircuitBreaker
import Tower.Middleware.Retry
import Tower.Middleware.Timeout

-- A simple API type (httpbin.org returns JSON for /get)
type HttpBinAPI = "get" :> Get '[JSON] Value

getEndpoint :: ClientM Value
getEndpoint = client (Proxy :: Proxy HttpBinAPI)

main :: IO ()
main = do
  putStrLn "=== tower-hs Servant client example ==="

  -- Create manager and circuit breaker
  manager <- newManager defaultManagerSettings
  baseUrl <- parseBaseUrl "https://httpbin.org"
  breaker <- newCircuitBreaker

  let config = CircuitBreakerConfig
        { cbFailureThreshold = 5
        , cbCooldownPeriod   = 30
        }
      env = mkClientEnv manager baseUrl & withTowerMiddleware
        ( -- Generic tower-hs middleware
          withRetry (exponentialBackoff 3 0.5 2.0)
        . withTimeout 10000
        . withCircuitBreaker config breaker
          -- Servant-specific middleware
        . STS.withUserAgent "tower-hs-example/0.1"
        . STS.withBearerAuth "example-token"
        . STV.withValidateStatus (\c -> c >= 200 && c < 300)
        . STL.withLogging T.putStrLn
        )

  -- Make a request
  result <- runClientM getEndpoint env

  case result of
    Left err  -> putStrLn $ "Failed: " <> show err
    Right val -> putStrLn $ "Success: " <> show val

  -- Check circuit breaker state
  state <- getCircuitBreakerState breaker
  putStrLn $ "Circuit breaker: " <> show state
