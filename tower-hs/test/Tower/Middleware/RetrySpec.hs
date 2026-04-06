{-# LANGUAGE OverloadedStrings #-}

module Tower.Middleware.RetrySpec (spec) where

import Data.IORef
import Data.Time.Clock (NominalDiffTime)
import Test.Hspec
import Test.QuickCheck

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Retry

spec :: Spec
spec = describe "Retry middleware" $ do
  describe "withRetry" $ do
    it "returns success immediately without retrying" $ do
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            modifyIORef' callCount (+ 1)
            pure (Right "ok")
          retried = withRetry (constantBackoff 3 0) svc
      result <- runService retried ()
      result `shouldBe` Right "ok"
      readIORef callCount >>= (`shouldBe` 1)

    it "retries on failure up to max retries" $ do
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            modifyIORef' callCount (+ 1)
            pure (Left (CustomError "fail"))
          retried = withRetry (constantBackoff 3 0) svc
      result <- runService retried ()
      case result of
        Left (RetryExhausted n _) -> n `shouldBe` 3
        other -> expectationFailure $ "Expected RetryExhausted, got: " ++ show other
      readIORef callCount >>= (`shouldBe` 4)  -- 1 initial + 3 retries

    it "succeeds after transient failures" $ do
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            n <- readIORef callCount
            modifyIORef' callCount (+ 1)
            if n < 2
              then pure (Left (CustomError "transient"))
              else pure (Right "recovered")
          retried = withRetry (constantBackoff 3 0) svc
      result <- runService retried ()
      result `shouldBe` Right "recovered"
      readIORef callCount >>= (`shouldBe` 3)  -- 2 failures + 1 success

    it "retries zero times when maxRetries is 0" $ do
      callCount <- newIORef (0 :: Int)
      let svc :: Service () String
          svc = Service $ \_ -> do
            modifyIORef' callCount (+ 1)
            pure (Left (CustomError "fail"))
          retried = withRetry (constantBackoff 0 0) svc
      result <- runService retried ()
      case result of
        Left (RetryExhausted 0 _) -> pure ()
        other -> expectationFailure $ "Expected RetryExhausted 0, got: " ++ show other
      readIORef callCount >>= (`shouldBe` 1)

  describe "computeDelay" $ do
    it "constant backoff returns same delay regardless of attempt" $ do
      let strategy = constantBackoff 3 2.0
      computeDelay strategy 0 `shouldBe` 2.0
      computeDelay strategy 1 `shouldBe` 2.0
      computeDelay strategy 5 `shouldBe` 2.0

    it "exponential backoff grows by multiplier" $ do
      let strategy = exponentialBackoff 5 1.0 2.0
      computeDelay strategy 0 `shouldBe` 1.0
      computeDelay strategy 1 `shouldBe` 2.0
      computeDelay strategy 2 `shouldBe` 4.0
      computeDelay strategy 3 `shouldBe` 8.0

    it "exponential delay is always positive" $ property $
      \(Positive base) (Positive mult) (NonNegative attempt) ->
        let strategy = exponentialBackoff 10 (realToFrac (base :: Double)) (mult :: Double)
        in computeDelay strategy (attempt :: Int) >= (0 :: NominalDiffTime)
