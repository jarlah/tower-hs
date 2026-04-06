{-# LANGUAGE OverloadedStrings #-}

module Tower.Middleware.FilterSpec (spec) where

import Test.Hspec

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Filter

spec :: Spec
spec = describe "Filter middleware" $ do
  describe "withFilter" $ do
    it "allows matching requests through" $ do
      let svc :: Service String String
          svc = Service $ \_ -> pure (Right "ok")
          filtered = withFilter (const True) svc
      result <- runService filtered "request"
      result `shouldBe` Right "ok"

    it "rejects non-matching requests" $ do
      let svc :: Service String String
          svc = Service $ \_ -> pure (Right "ok")
          filtered = withFilter (const False) svc
      result <- runService filtered "request"
      result `shouldBe` Left (CustomError "Request filtered out")

    it "filters based on request properties" $ do
      let svc :: Service String String
          svc = Service $ \_ -> pure (Right "ok")
          onlyGet = withFilter (== "GET") svc
      getResult <- runService onlyGet "GET"
      postResult <- runService onlyGet "POST"
      getResult `shouldBe` Right "ok"
      postResult `shouldBe` Left (CustomError "Request filtered out")
