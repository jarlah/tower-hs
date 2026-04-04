{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.TracingSpec (spec) where

import Data.IORef
import qualified Data.ByteString.Lazy as LBS
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.Internal as HTTP
import qualified Network.HTTP.Types as HTTP
import Test.Hspec

import OpenTelemetry.Trace.Core
  ( makeTracer
  , getGlobalTracerProvider
  , InstrumentationLibrary(..)
  , TracerOptions(..)
  )
import OpenTelemetry.Attributes (emptyAttributes)

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Error
import Network.HTTP.Tower.Middleware.Tracing

spec :: Spec
spec = describe "Tracing middleware" $ do
  -- No OTel SDK configured, so tracing is a no-op — but the middleware
  -- still wraps the service and must be transparent.

  it "passes successful responses through unchanged" $ do
    let svc = Service $ \_ -> pure (Right fakeResponse)
    tracingMw <- withTracing
    let traced = tracingMw svc
    req <- HTTP.parseRequest "http://example.com/test"
    result <- runService traced req
    case result of
      Right resp -> HTTP.responseStatus resp `shouldBe` HTTP.status200
      Left err   -> expectationFailure $ "Expected Right, got: " ++ show err

  it "passes errors through unchanged" $ do
    let svc :: Service HTTP.Request HttpResponse
        svc = Service $ \_ -> pure (Left TimeoutError)
    tracingMw <- withTracing
    let traced = tracingMw svc
    req <- HTTP.parseRequest "http://example.com/fail"
    result <- runService traced req
    case result of
      Left TimeoutError -> pure ()
      other -> expectationFailure $ "Expected Left TimeoutError, got: " ++ show other

  it "calls the inner service exactly once" $ do
    callCount <- newIORef (0 :: Int)
    let svc = Service $ \_ -> do
          modifyIORef' callCount (+ 1)
          pure (Right fakeResponse)
    tracingMw <- withTracing
    let traced = tracingMw svc
    req <- HTTP.parseRequest "http://example.com/once"
    _ <- runService traced req
    readIORef callCount >>= (`shouldBe` 1)

  it "works with withTracingTracer using a specific tracer" $ do
    tp <- getGlobalTracerProvider
    let tracer = makeTracer tp
          (InstrumentationLibrary
            { libraryName = "test"
            , libraryVersion = "0.0.0"
            , librarySchemaUrl = ""
            , libraryAttributes = emptyAttributes
            })
          (TracerOptions Nothing)
        svc = Service $ \_ -> pure (Right fakeResponse)
        traced = withTracingTracer tracer svc
    req <- HTTP.parseRequest "https://api.example.com/v1/data"
    result <- runService traced req
    case result of
      Right resp -> HTTP.responseStatus resp `shouldBe` HTTP.status200
      Left err   -> expectationFailure $ "Expected Right, got: " ++ show err

  it "handles 4xx responses without altering the result" $ do
    let svc = Service $ \_ -> pure (Right fake404Response)
    tracingMw <- withTracing
    let traced = tracingMw svc
    req <- HTTP.parseRequest "http://example.com/notfound"
    result <- runService traced req
    case result of
      Right resp -> HTTP.responseStatus resp `shouldBe` HTTP.notFound404
      Left err   -> expectationFailure $ "Expected Right, got: " ++ show err

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

fake404Response :: HttpResponse
fake404Response = fakeResponse
  { HTTP.responseStatus = HTTP.notFound404
  }

instance Eq ServiceError where
  CustomError a      == CustomError b      = a == b
  TimeoutError       == TimeoutError       = True
  CircuitBreakerOpen == CircuitBreakerOpen  = True
  RetryExhausted n _ == RetryExhausted m _ = n == m
  _                  == _                  = False
