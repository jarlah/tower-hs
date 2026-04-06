{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Tower.Middleware.HedgeSpec (spec) where

import Control.Concurrent (threadDelay)
import Data.IORef
import Test.Hspec

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Hedge

spec :: Spec
spec = describe "Hedge middleware" $ do
  it "returns result from fast primary without hedging" $ do
    let svc :: Service () String
        svc = Service $ \_ -> pure (Right "fast")
        hedged = withHedge 1000 svc
    result <- runService hedged ()
    result `shouldBe` Right "fast"

  it "returns a result when primary is slow (hedge may win)" $ do
    callCount <- newIORef (0 :: Int)
    let svc :: Service () String
        svc = Service $ \_ -> do
          n <- atomicModifyIORef' callCount (\c -> (c + 1, c))
          if n == 0
            then do
              threadDelay 500_000  -- primary: slow
              pure (Right "primary")
            else pure (Right "hedge")  -- hedge: instant
        hedged = withHedge 50 svc
    result <- runService hedged ()
    case result of
      Right _ -> pure ()
      Left err -> expectationFailure $ "Expected Right, got: " ++ show err

  it "calls service at most twice" $ do
    callCount <- newIORef (0 :: Int)
    let svc :: Service () String
        svc = Service $ \_ -> do
          modifyIORef' callCount (+ 1)
          threadDelay 100_000
          pure (Right "done")
        hedged = withHedge 50 svc
    _ <- runService hedged ()
    threadDelay 200_000
    count <- readIORef callCount
    count `shouldSatisfy` (<= 2)
