{-# LANGUAGE OverloadedStrings #-}

module Tower.ServiceSpec (spec) where

import Test.Hspec

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()

spec :: Spec
spec = describe "Core" $ do
  describe "Service" $ do
    it "runs a simple service" $ do
      let svc = Service $ \n -> pure (Right (n * 2 :: Int))
      result <- runService svc 21
      result `shouldBe` Right 42

    it "returns errors in Left" $ do
      let svc :: Service () String
          svc = Service $ \_ -> pure (Left (CustomError "boom"))
      result <- runService svc ()
      result `shouldBe` Left (CustomError "boom")

  describe "mapService" $ do
    it "transforms successful responses" $ do
      let svc :: Service () Int
          svc = Service $ \_ -> pure (Right 10)
          mapped = mapService (* 3) svc
      result <- runService mapped ()
      result `shouldBe` Right 30

    it "passes through errors unchanged" $ do
      let svc :: Service () Int
          svc = Service $ \_ -> pure (Left TimeoutError)
          mapped = mapService (* 3) svc
      result <- runService mapped ()
      result `shouldBe` Left TimeoutError

  describe "composeMiddleware" $ do
    it "applies outer then inner" $ do
      let addTag tag (Service run) = Service $ \req ->
            run (req ++ tag)
          mw1 = addTag "[1]"
          mw2 = addTag "[2]"
          composed = composeMiddleware mw1 mw2
          svc = Service $ \req -> pure (Right req)
      result <- runService (composed svc) "start"
      result `shouldBe` Right "start[1][2]"
