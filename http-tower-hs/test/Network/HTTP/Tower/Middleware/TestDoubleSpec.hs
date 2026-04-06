{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.TestDoubleSpec (spec) where

import Data.IORef
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.Internal as HTTP
import qualified Network.HTTP.Types as HTTP
import Test.Hspec

import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service
import Tower.Error
import Network.HTTP.Tower.Middleware.TestDouble

spec :: Spec
spec = describe "TestDouble middleware" $ do
  describe "withMock" $ do
    it "replaces the inner service entirely" $ do
      innerCalled <- newIORef False
      let inner = Service $ \_ -> do
            writeIORef innerCalled True
            pure (Right fakeResponse)
          mocked = withMock (\_ -> pure (Right fakeResponse)) inner
      req <- HTTP.parseRequest "http://example.com"
      result <- runService mocked req
      case result of
        Right _ -> pure ()
        Left err -> expectationFailure $ show err
      readIORef innerCalled >>= (`shouldBe` False)

    it "can return errors" $ do
      let mocked = withMock (\_ -> pure (Left (CustomError "mock error"))) (Service $ \_ -> pure (Right fakeResponse))
      req <- HTTP.parseRequest "http://example.com"
      result <- runService mocked req
      case result of
        Left (CustomError "mock error") -> pure ()
        other -> expectationFailure $ "Expected mock error, got: " ++ show other

  describe "withMockMap" $ do
    it "routes to matching mock response" $ do
      let mocks = Map.fromList
            [ ("example.com/api/users", Right fakeResponse)
            ]
          mocked = withMockMap mocks (Service $ \_ -> pure (Left (CustomError "not mocked")))
      req <- HTTP.parseRequest "http://example.com/api/users"
      result <- runService mocked req
      case result of
        Right _ -> pure ()
        Left err -> expectationFailure $ "Expected mock match, got: " ++ show err

    it "falls through to inner service on no match" $ do
      let mocks = Map.fromList
            [ ("example.com/api/users", Right fakeResponse)
            ]
          mocked = withMockMap mocks (Service $ \_ -> pure (Right fakeResponse))
      req <- HTTP.parseRequest "http://example.com/api/other"
      result <- runService mocked req
      case result of
        Right _ -> pure ()
        Left err -> expectationFailure $ show err

  describe "withRecorder" $ do
    it "records all requests" $ do
      recorder <- newIORef []
      let svc = withRecorder recorder (Service $ \_ -> pure (Right fakeResponse))
      req1 <- HTTP.parseRequest "http://example.com/a"
      req2 <- HTTP.parseRequest "http://example.com/b"
      _ <- runService svc req1
      _ <- runService svc req2
      recorded <- readIORef recorder
      length recorded `shouldBe` 2

    it "still forwards to inner service" $ do
      recorder <- newIORef []
      innerCalled <- newIORef (0 :: Int)
      let inner = Service $ \_ -> do
            modifyIORef' innerCalled (+ 1)
            pure (Right fakeResponse)
          svc = withRecorder recorder inner
      req <- HTTP.parseRequest "http://example.com"
      _ <- runService svc req
      readIORef innerCalled >>= (`shouldBe` 1)

fakeResponse :: HttpResponse
fakeResponse = HTTP.Response
  { HTTP.responseStatus = HTTP.status200
  , HTTP.responseVersion = HTTP.http11
  , HTTP.responseHeaders = []
  , HTTP.responseBody = ""
  , HTTP.responseCookieJar = HTTP.createCookieJar []
  , HTTP.responseClose' = HTTP.ResponseClose (pure ())
  , HTTP.responseOriginalRequest = error "not used"
  , HTTP.responseEarlyHints = []
  }
