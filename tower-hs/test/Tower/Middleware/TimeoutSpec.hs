{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Tower.Middleware.TimeoutSpec (spec) where

import Control.Concurrent (threadDelay)
import Test.Hspec

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Timeout

spec :: Spec
spec = describe "Timeout middleware" $ do
  it "allows fast requests through" $ do
    let svc :: Service () String
        svc = Service $ \_ -> pure (Right "fast")
        timed = withTimeout 1000 svc
    result <- runService timed ()
    result `shouldBe` Right "fast"

  it "times out slow requests" $ do
    let svc :: Service () String
        svc = Service $ \_ -> do
          threadDelay 500_000  -- 500ms
          pure (Right "slow")
        timed = withTimeout 100 svc  -- 100ms timeout
    result <- runService timed ()
    result `shouldBe` Left TimeoutError

  it "preserves errors from inner service" $ do
    let svc :: Service () String
        svc = Service $ \_ -> pure (Left (CustomError "inner error"))
        timed = withTimeout 1000 svc
    result <- runService timed ()
    result `shouldBe` Left (CustomError "inner error")
