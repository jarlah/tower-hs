{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.LoggingSpec (spec) where

import Data.IORef
import Data.Text (Text, isInfixOf)
import qualified Data.ByteString.Lazy as LBS
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.Internal as HTTP
import qualified Network.HTTP.Types as HTTP
import Test.Hspec

import Network.HTTP.Tower.Client (HttpResponse)
import Tower.Service
import Tower.Error
import Network.HTTP.Tower.Middleware.Logging

spec :: Spec
spec = describe "Logging middleware" $ do
  it "logs successful requests" $ do
    logRef <- newIORef ([] :: [Text])
    let logger msg = modifyIORef' logRef (msg :)
        svc = Service $ \_ -> pure (Right fakeResponse)
        logged = withLogging logger svc
    req <- HTTP.parseRequest "http://example.com/test"
    _ <- runService logged req
    logs <- readIORef logRef
    length logs `shouldBe` 1
    let logMsg = head logs
    isInfixOf "example.com" logMsg `shouldBe` True

  it "logs failed requests" $ do
    logRef <- newIORef ([] :: [Text])
    let logger msg = modifyIORef' logRef (msg :)
        svc :: Service HTTP.Request HttpResponse
        svc = Service $ \_ -> pure (Left TimeoutError)
        logged = withLogging logger svc
    req <- HTTP.parseRequest "http://example.com/fail"
    _ <- runService logged req
    logs <- readIORef logRef
    length logs `shouldBe` 1
    let logMsg = head logs
    isInfixOf "ERR" logMsg `shouldBe` True

  it "does not alter the result" $ do
    let logger _ = pure ()
        svc = Service $ \_ -> pure (Right fakeResponse)
        logged = withLogging logger svc
    req <- HTTP.parseRequest "http://example.com/passthrough"
    result <- runService logged req
    case result of
      Right _  -> pure ()
      Left err -> expectationFailure $ "Expected Right, got: " ++ show err

fakeResponse :: HTTP.Response LBS.ByteString
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
