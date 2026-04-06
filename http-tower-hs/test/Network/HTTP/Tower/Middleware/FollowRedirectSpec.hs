{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.FollowRedirectSpec (spec) where

import Data.IORef
import qualified Data.ByteString.Lazy as LBS
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.Internal as HTTP
import qualified Network.HTTP.Types as HTTP
import Test.Hspec

import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Network.HTTP.Tower.Middleware.FollowRedirect

spec :: Spec
spec = describe "FollowRedirect middleware" $ do
  it "passes non-redirect responses through" $ do
    let svc = Service $ \_ -> pure (Right (fakeResponseWith HTTP.status200 []))
        followed = withFollowRedirects 5 svc
    req <- HTTP.parseRequest "http://example.com"
    result <- runService followed req
    case result of
      Right resp -> HTTP.responseStatus resp `shouldBe` HTTP.status200
      Left err -> expectationFailure $ show err

  it "follows a 302 redirect" $ do
    callCount <- newIORef (0 :: Int)
    let svc = Service $ \req -> do
          n <- readIORef callCount
          modifyIORef' callCount (+ 1)
          if n == 0
            then pure $ Right $ fakeResponseWith
              (HTTP.mkStatus 302 "Found")
              [("Location", "http://example.com/redirected")]
            else pure $ Right $ fakeResponseWith HTTP.status200 []
        followed = withFollowRedirects 5 svc
    req <- HTTP.parseRequest "http://example.com/original"
    result <- runService followed req
    case result of
      Right resp -> HTTP.responseStatus resp `shouldBe` HTTP.status200
      Left err -> expectationFailure $ show err
    readIORef callCount >>= (`shouldBe` 2)

  it "stops after max redirects" $ do
    let svc = Service $ \_ -> pure $ Right $ fakeResponseWith
          (HTTP.mkStatus 301 "Moved")
          [("Location", "http://example.com/loop")]
        followed = withFollowRedirects 3 svc
    req <- HTTP.parseRequest "http://example.com/loop"
    result <- runService followed req
    case result of
      Left (CustomError msg) -> msg `shouldBe` "Too many redirects"
      other -> expectationFailure $ "Expected CustomError, got: " ++ show other

  it "changes method to GET on 303" $ do
    recorder <- newIORef []
    let svc = Service $ \req -> do
          modifyIORef' recorder (HTTP.method req :)
          n <- length <$> readIORef recorder
          if n == 1
            then pure $ Right $ fakeResponseWith
              (HTTP.mkStatus 303 "See Other")
              [("Location", "http://example.com/result")]
            else pure $ Right $ fakeResponseWith HTTP.status200 []
        followed = withFollowRedirects 5 svc
    req <- HTTP.parseRequest "http://example.com/action"
    let postReq = req { HTTP.method = "POST" }
    _ <- runService followed postReq
    methods <- readIORef recorder
    -- First request was POST, second (after 303) should be GET
    reverse methods `shouldBe` ["POST", "GET"]

fakeResponseWith :: HTTP.Status -> [HTTP.Header] -> HttpResponse
fakeResponseWith status hdrs = HTTP.Response
  { HTTP.responseStatus = status
  , HTTP.responseVersion = HTTP.http11
  , HTTP.responseHeaders = hdrs
  , HTTP.responseBody = ""
  , HTTP.responseCookieJar = HTTP.createCookieJar []
  , HTTP.responseClose' = HTTP.ResponseClose (pure ())
  , HTTP.responseOriginalRequest = error "not used"
  , HTTP.responseEarlyHints = []
  }
