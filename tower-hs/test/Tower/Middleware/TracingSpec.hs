{-# LANGUAGE OverloadedStrings #-}

module Tower.Middleware.TracingSpec (spec) where

import Data.IORef
import Data.Text (Text)
import Test.Hspec

import OpenTelemetry.Attributes (emptyAttributes)
import OpenTelemetry.Trace.Core (InstrumentationLibrary(..))

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Tracing

spec :: Spec
spec = describe "Tracing middleware (generic)" $ do
  -- No OTel SDK configured, so tracing is a no-op — but the middleware
  -- must be transparent.

  it "passes successful responses through unchanged" $ do
    let config = defaultTracingConfig "test-span"
        svc :: Service () String
        svc = Service $ \_ -> pure (Right "hello")
        traced = withTracingGlobal testLib config svc
    result <- runService traced ()
    result `shouldBe` Right "hello"

  it "passes errors through unchanged" $ do
    let config = defaultTracingConfig "test-span"
        svc :: Service () String
        svc = Service $ \_ -> pure (Left TimeoutError)
        traced = withTracingGlobal testLib config svc
    result <- runService traced ()
    result `shouldBe` Left TimeoutError

  it "calls the inner service exactly once" $ do
    callCount <- newIORef (0 :: Int)
    let config = defaultTracingConfig "test-span"
        svc :: Service () String
        svc = Service $ \_ -> do
          modifyIORef' callCount (+ 1)
          pure (Right "ok")
        traced = withTracingGlobal testLib config svc
    _ <- runService traced ()
    readIORef callCount >>= (`shouldBe` 1)

  it "uses request-dependent span name from config" $ do
    let config = (defaultTracingConfig "unused")
          { tracingSpanName = ("span-" <>) }
        svc :: Service Text String
        svc = Service $ \_ -> pure (Right "ok")
        traced = withTracingGlobal testLib config svc
    result <- runService traced "test"
    result `shouldBe` Right "ok"

  it "calls request attribute hook" $ do
    hookCalled <- newIORef False
    let config = (defaultTracingConfig "test")
          { tracingReqAttrs = \_ _ -> writeIORef hookCalled True }
        svc :: Service () String
        svc = Service $ \_ -> pure (Right "ok")
        traced = withTracingGlobal testLib config svc
    _ <- runService traced ()
    readIORef hookCalled >>= (`shouldBe` True)

  it "calls response attribute hook on success" $ do
    hookCalled <- newIORef False
    let config = (defaultTracingConfig "test")
          { tracingResAttrs = \_ _ -> writeIORef hookCalled True }
        svc :: Service () String
        svc = Service $ \_ -> pure (Right "ok")
        traced = withTracingGlobal testLib config svc
    _ <- runService traced ()
    readIORef hookCalled >>= (`shouldBe` True)

  it "does not call response attribute hook on error" $ do
    hookCalled <- newIORef False
    let config = (defaultTracingConfig "test")
          { tracingResAttrs = \_ _ -> writeIORef hookCalled True }
        svc :: Service () String
        svc = Service $ \_ -> pure (Left (CustomError "fail"))
        traced = withTracingGlobal testLib config svc
    _ <- runService traced ()
    readIORef hookCalled >>= (`shouldBe` False)

testLib :: InstrumentationLibrary
testLib = InstrumentationLibrary
  { libraryName = "tower-hs-test"
  , libraryVersion = "0.0.0"
  , librarySchemaUrl = ""
  , libraryAttributes = emptyAttributes
  }
