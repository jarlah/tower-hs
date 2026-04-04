{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.SetHeaderSpec (spec) where

import Data.IORef
import qualified Network.HTTP.Client as HTTP
import Test.Hspec

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Middleware.SetHeader
import Network.HTTP.Tower.Middleware.TestDouble (withRecorder)

spec :: Spec
spec = describe "SetHeader middleware" $ do
  it "adds a single header to requests" $ do
    recorder <- newIORef []
    let svc = withHeader "X-Custom" "value" (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    recorded <- readIORef recorder
    let hdrs = HTTP.requestHeaders (head recorded)
    lookup "X-Custom" hdrs `shouldBe` Just "value"

  it "adds multiple headers" $ do
    recorder <- newIORef []
    let svc = withHeaders [("X-A", "1"), ("X-B", "2")] (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    recorded <- readIORef recorder
    let hdrs = HTTP.requestHeaders (head recorded)
    lookup "X-A" hdrs `shouldBe` Just "1"
    lookup "X-B" hdrs `shouldBe` Just "2"

  it "adds Bearer auth header" $ do
    recorder <- newIORef []
    let svc = withBearerAuth "my-token" (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    recorded <- readIORef recorder
    let hdrs = HTTP.requestHeaders (head recorded)
    lookup "Authorization" hdrs `shouldBe` Just "Bearer my-token"

  it "sets User-Agent header" $ do
    recorder <- newIORef []
    let svc = withUserAgent "http-tower/0.1" (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    recorded <- readIORef recorder
    let hdrs = HTTP.requestHeaders (head recorded)
    lookup "User-Agent" hdrs `shouldBe` Just "http-tower/0.1"

fakeResponse :: HttpResponse
fakeResponse = error "fakeResponse: body not evaluated in SetHeader tests"
