{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Network.HTTP.Tower.Middleware.CircuitBreakerSpec (spec) where

import Control.Concurrent (threadDelay)
import Data.IORef
import Test.Hspec

import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Error
import Network.HTTP.Tower.Middleware.CircuitBreaker

spec :: Spec
spec = describe "Circuit Breaker middleware" $ do
  let config = CircuitBreakerConfig
        { cbFailureThreshold = 3
        , cbCooldownPeriod   = 1  -- 1 second
        }

  describe "Closed state" $ do
    it "passes requests through when healthy" $ do
      breaker <- newCircuitBreaker
      let svc :: Service () String
          svc = Service $ \_ -> pure (Right "ok")
          wrapped = withCircuitBreaker config breaker svc
      result <- runService wrapped ()
      result `shouldBe` Right "ok"
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)

    it "stays closed on fewer failures than threshold" $ do
      breaker <- newCircuitBreaker
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            modifyIORef' callCount (+ 1)
            pure (Left (CustomError "fail"))
          wrapped = withCircuitBreaker config breaker svc
      -- 2 failures, threshold is 3
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)
      readIORef callCount >>= (`shouldBe` 2)

  describe "Tripping open" $ do
    it "trips open after reaching failure threshold" $ do
      breaker <- newCircuitBreaker
      let svc :: Service () String
          svc = Service $ \_ -> pure (Left (CustomError "fail"))
          wrapped = withCircuitBreaker config breaker svc
      -- 3 failures = threshold
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      getCircuitBreakerState breaker >>= (`shouldBe` Open)

    it "rejects requests immediately when open" $ do
      breaker <- newCircuitBreaker
      callCount <- newIORef (0 :: Int)
      let failSvc :: Service () String
          failSvc = Service $ \_ -> do
            modifyIORef' callCount (+ 1)
            pure (Left (CustomError "fail"))
          wrapped = withCircuitBreaker config breaker failSvc
      -- Trip the breaker
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      -- Next request should be rejected without calling the service
      countBefore <- readIORef callCount
      result <- runService wrapped ()
      countAfter <- readIORef callCount
      result `shouldBe` Left CircuitBreakerOpen
      countAfter `shouldBe` countBefore  -- service was NOT called

  describe "Half-open state" $ do
    it "transitions to half-open after cooldown" $ do
      let fastConfig = config { cbCooldownPeriod = 0.1 }  -- 100ms cooldown
      breaker <- newCircuitBreaker
      let svc :: Service () String
          svc = Service $ \_ -> pure (Left (CustomError "fail"))
          wrapped = withCircuitBreaker fastConfig breaker svc
      -- Trip the breaker
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      getCircuitBreakerState breaker >>= (`shouldBe` Open)
      -- Wait for cooldown
      threadDelay 150_000  -- 150ms
      -- Next request should go through (half-open allows one probe)
      _ <- runService wrapped ()
      -- It failed again, so back to Open
      getCircuitBreakerState breaker >>= (`shouldBe` Open)

    it "resets to closed on success in half-open" $ do
      let fastConfig = config { cbCooldownPeriod = 0.1 }
      breaker <- newCircuitBreaker
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            n <- readIORef callCount
            modifyIORef' callCount (+ 1)
            if n < 3
              then pure (Left (CustomError "fail"))
              else pure (Right "recovered")
          wrapped = withCircuitBreaker fastConfig breaker svc
      -- Trip the breaker (3 failures)
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      _ <- runService wrapped ()
      getCircuitBreakerState breaker >>= (`shouldBe` Open)
      -- Wait for cooldown
      threadDelay 150_000
      -- Next request succeeds — should reset to Closed
      result <- runService wrapped ()
      result `shouldBe` Right "recovered"
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)

  describe "Reset on success" $ do
    it "resets failure count on any success" $ do
      breaker <- newCircuitBreaker
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            n <- readIORef callCount
            modifyIORef' callCount (+ 1)
            if n == 1  -- second call succeeds
              then pure (Right "ok")
              else pure (Left (CustomError "fail"))
          wrapped = withCircuitBreaker config breaker svc
      -- Fail once
      _ <- runService wrapped ()
      -- Succeed — resets counter
      _ <- runService wrapped ()
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)
      -- Now need 3 MORE failures to trip (not 2)
      _ <- runService wrapped ()  -- fail
      _ <- runService wrapped ()  -- fail
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)

instance Eq ServiceError where
  CustomError a      == CustomError b      = a == b
  TimeoutError       == TimeoutError       = True
  CircuitBreakerOpen == CircuitBreakerOpen  = True
  RetryExhausted n _ == RetryExhausted m _ = n == m
  _                  == _                  = False
