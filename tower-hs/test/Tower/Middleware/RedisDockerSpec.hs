{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Integration test demonstrating tower-hs generic middleware with a real
-- Redis database via testcontainers. This proves that retry, timeout,
-- circuit breaker, logging, and validation compose for non-HTTP services
-- just as naturally as they do for HTTP or servant.
module Tower.Middleware.RedisDockerSpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.IORef
import Data.Text (Text, isInfixOf)
import qualified Data.Text as T
import System.Process (readProcess)
import Test.Hspec

import qualified Database.Redis as Redis

import qualified TestContainers as TC
import TestContainers.Hspec (withContainers)

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.CircuitBreaker
import Tower.Middleware.Logging (withLogging)
import Tower.Middleware.Retry
import Tower.Middleware.Timeout
import Tower.Middleware.Validate (withValidate)

-- ---------------------------------------------------------------------------
-- Redis container setup
-- ---------------------------------------------------------------------------

setupRedis :: TC.TestContainer Redis.Connection
setupRedis = do
  container <- TC.run $ TC.containerRequest (TC.fromTag "redis:7-alpine")
    TC.& TC.setExpose [6379]
    TC.& TC.setWaitingFor (TC.waitUntilTimeout 30 (TC.waitUntilMappedPortReachable 6379))
  let port = TC.containerPort container 6379
  liftIO $ do
    -- Small delay to ensure Redis is accepting commands
    threadDelay 500_000
    Redis.checkedConnect Redis.defaultConnectInfo
      { Redis.connectHost = "localhost"
      , Redis.connectPort = Redis.PortNumber (fromIntegral port)
      }

-- ---------------------------------------------------------------------------
-- Redis service wrapped as tower-hs Service
-- ---------------------------------------------------------------------------

-- | A Redis SET+GET service: takes a (key, value) pair, stores it, and
-- returns the value read back. Exercises a real database round-trip.
type RedisGetSet = Service (ByteString, ByteString) ByteString

mkRedisService :: Redis.Connection -> RedisGetSet
mkRedisService conn = Service $ \(key, value) -> do
  result <- try $ Redis.runRedis conn $ do
    _ <- Redis.set key value
    Redis.get key
  pure $ case result of
    Left (err :: SomeException) -> Left (TransportError err)
    Right (Right (Just v))      -> Right v
    Right (Right Nothing)       -> Left (CustomError "key not found after SET")
    Right (Left reply)          -> Left (CustomError ("Redis error: " <> T.pack (show reply)))

-- | A simple Redis PING service for connectivity checks.
type RedisPing = Service () Redis.Status

mkRedisPingService :: Redis.Connection -> RedisPing
mkRedisPingService conn = Service $ \_ -> do
  result <- try $ Redis.runRedis conn Redis.ping
  pure $ case result of
    Left (err :: SomeException) -> Left (TransportError err)
    Right (Right status)        -> Right status
    Right (Left reply)          -> Left (CustomError ("Redis error: " <> T.pack (show reply)))

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

dockerAvailable :: IO Bool
dockerAvailable = do
  result <- try (readProcess "docker" ["info"] "") :: IO (Either SomeException String)
  pure $ case result of
    Right _ -> True
    Left _  -> False

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Redis integration (testcontainers)" $ beforeAll dockerAvailable $ do

  it "SET and GET through a tower-hs service" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else withContainers setupRedis $ \conn -> do
        let svc = mkRedisService conn
        result <- runService svc ("tower-key", "tower-value")
        result `shouldBe` Right "tower-value"

  it "retry recovers from transient errors" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else withContainers setupRedis $ \conn -> do
        callCount <- newIORef (0 :: Int)
        let svc = Service $ \input -> do
              n <- atomicModifyIORef' callCount (\c -> (c + 1, c))
              if n < 2
                then pure (Left (CustomError "transient redis error"))
                else runService (mkRedisService conn) input
            robust = withRetry (constantBackoff 3 0) svc
        result <- runService robust ("retry-key", "retry-value")
        result `shouldBe` Right "retry-value"
        readIORef callCount >>= (`shouldBe` 3)

  it "timeout catches slow operations" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else withContainers setupRedis $ \conn -> do
        -- Wrap a service that artificially delays
        let slowSvc :: RedisGetSet
            slowSvc = Service $ \input -> do
              threadDelay 2_000_000  -- 2 seconds
              runService (mkRedisService conn) input
            timed = withTimeout 500 slowSvc  -- 500ms timeout
        result <- runService timed ("timeout-key", "timeout-value")
        result `shouldBe` Left TimeoutError

  it "circuit breaker trips after repeated failures" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else withContainers setupRedis $ \_ -> do
        breaker <- newCircuitBreaker
        let config = CircuitBreakerConfig { cbFailureThreshold = 2, cbCooldownPeriod = 10 }
            failSvc :: RedisGetSet
            failSvc = Service $ \_ -> pure (Left (CustomError "redis down"))
            protected = withCircuitBreaker config breaker failSvc
        _ <- runService protected ("k", "v")
        _ <- runService protected ("k", "v")
        getCircuitBreakerState breaker >>= (`shouldBe` Open)
        result <- runService protected ("k", "v")
        result `shouldBe` Left CircuitBreakerOpen

  it "validates results" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else withContainers setupRedis $ \conn -> do
        let svc = mkRedisService conn
            validated = withValidate (\v ->
              if v == "expected" then Nothing
              else Just ("Unexpected value: " <> T.pack (show v))) svc
        -- This should fail validation — the stored value won't be "expected"
        result <- runService validated ("val-key", "something-else")
        case result of
          Left (CustomError msg) -> isInfixOf "Unexpected value" msg `shouldBe` True
          other -> expectationFailure $ "Expected validation error, got: " <> show other

  it "composes full middleware stack for Redis service" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else withContainers setupRedis $ \conn -> do
        logRef <- newIORef ([] :: [Text])
        breaker <- newCircuitBreaker
        let config = CircuitBreakerConfig { cbFailureThreshold = 5, cbCooldownPeriod = 30 }
            svc = mkRedisPingService conn
            robust = withRetry (constantBackoff 2 0)
                   . withTimeout 5000
                   . withCircuitBreaker config breaker
                   . withValidate (\status ->
                       if status == Redis.Pong then Nothing
                       else Just ("Unexpected PING response: " <> T.pack (show status)))
                   . withLogging
                       (\_ result dur -> case result of
                         Right _ -> "Redis OK (" <> T.pack (show (round (dur * 1000) :: Int)) <> "ms)"
                         Left err -> "Redis ERR: " <> displayError err)
                       (\msg -> modifyIORef' logRef (msg :))
                   $ svc
        result <- runService robust ()
        result `shouldBe` Right Redis.Pong
        getCircuitBreakerState breaker >>= (`shouldBe` Closed)
        logs <- readIORef logRef
        length logs `shouldBe` 1
        isInfixOf "Redis OK" (head logs) `shouldBe` True
