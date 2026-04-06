{-# LANGUAGE OverloadedStrings #-}

module Tower.Middleware.ValidateSpec (spec) where

import Test.Hspec

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Validate

spec :: Spec
spec = describe "Validate middleware (generic)" $ do
  it "passes responses that return Nothing" $ do
    let svc :: Service () String
        svc = Service $ \_ -> pure (Right "ok")
        validated = withValidate (const Nothing) svc
    result <- runService validated ()
    result `shouldBe` Right "ok"

  it "rejects responses that return Just" $ do
    let svc :: Service () String
        svc = Service $ \_ -> pure (Right "bad")
        validated = withValidate (\_ -> Just "validation failed") svc
    result <- runService validated ()
    result `shouldBe` Left (CustomError "validation failed")

  it "passes through errors from inner service" $ do
    let svc :: Service () String
        svc = Service $ \_ -> pure (Left TimeoutError)
        validated = withValidate (const (Just "should not trigger")) svc
    result <- runService validated ()
    result `shouldBe` Left TimeoutError

  it "can inspect the response value" $ do
    let svc :: Service () Int
        svc = Service $ \_ -> pure (Right 42)
        validated = withValidate (\n -> if n > 100 then Just "too big" else Nothing) svc
    result <- runService validated ()
    result `shouldBe` Right 42

  it "rejects based on response value" $ do
    let svc :: Service () Int
        svc = Service $ \_ -> pure (Right 200)
        validated = withValidate (\n -> if n > 100 then Just "too big" else Nothing) svc
    result <- runService validated ()
    result `shouldBe` Left (CustomError "too big")
