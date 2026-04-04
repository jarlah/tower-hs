{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.FilterSpec (spec) where

import qualified Network.HTTP.Client as HTTP
import Test.Hspec

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Error
import Network.HTTP.Tower.Middleware.Filter

spec :: Spec
spec = describe "Filter middleware" $ do
  describe "withFilter" $ do
    it "allows matching requests through" $ do
      let svc :: Service HTTP.Request String
          svc = Service $ \_ -> pure (Right "ok")
          filtered = withFilter (const True) svc
      req <- HTTP.parseRequest "http://example.com"
      result <- runService filtered req
      result `shouldBe` Right "ok"

    it "rejects non-matching requests" $ do
      let svc :: Service HTTP.Request String
          svc = Service $ \_ -> pure (Right "ok")
          filtered = withFilter (const False) svc
      req <- HTTP.parseRequest "http://example.com"
      result <- runService filtered req
      result `shouldBe` Left (CustomError "Request filtered out")

    it "filters based on request properties" $ do
      let svc :: Service HTTP.Request String
          svc = Service $ \_ -> pure (Right "ok")
          onlyGet = withFilter (\r -> HTTP.method r == "GET") svc
      getReq <- HTTP.parseRequest "http://example.com"
      postReq <- HTTP.parseRequest "http://example.com"
      let postReq' = postReq { HTTP.method = "POST" }
      getResult <- runService onlyGet getReq
      postResult <- runService onlyGet postReq'
      getResult `shouldBe` Right "ok"
      postResult `shouldBe` Left (CustomError "Request filtered out")

instance Eq ServiceError where
  CustomError a == CustomError b = a == b
  _ == _ = False
