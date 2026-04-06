{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.RequestIdSpec (spec) where

import Data.IORef
import qualified Network.HTTP.Client as HTTP
import Test.Hspec

import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service
import Network.HTTP.Tower.Middleware.RequestId
import Network.HTTP.Tower.Middleware.TestDouble (withRecorder)

spec :: Spec
spec = describe "RequestId middleware" $ do
  it "adds X-Request-ID header" $ do
    recorder <- newIORef []
    let svc = withRequestId (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    recorded <- readIORef recorder
    let hdrs = HTTP.requestHeaders (head recorded)
    lookup "X-Request-ID" hdrs `shouldSatisfy` (/= Nothing)

  it "generates unique IDs per request" $ do
    recorder <- newIORef []
    let svc = withRequestId (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    _ <- runService svc req
    recorded <- readIORef recorder
    let ids = map (lookup "X-Request-ID" . HTTP.requestHeaders) recorded
    length ids `shouldBe` 2
    head ids `shouldSatisfy` (/= last ids)

  it "uses custom header name" $ do
    recorder <- newIORef []
    let svc = withRequestIdHeader "X-Correlation-ID" (withRecorder recorder (Service $ \_ -> pure (Right fakeResponse)))
    req <- HTTP.parseRequest "http://example.com"
    _ <- runService svc req
    recorded <- readIORef recorder
    let hdrs = HTTP.requestHeaders (head recorded)
    lookup "X-Correlation-ID" hdrs `shouldSatisfy` (/= Nothing)

fakeResponse :: HttpResponse
fakeResponse = error "fakeResponse: body not evaluated in RequestId tests"
