{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Servant.Tower.Middleware.TracingIntegrationSpec (spec) where

import Control.Concurrent (threadDelay)
import Data.IORef
import Data.Proxy (Proxy(..))
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.Wai.Handler.Warp (testWithApplication)
import Servant
import Servant.Client
import Test.Hspec

import OpenTelemetry.Attributes (emptyAttributes, lookupAttribute)
import OpenTelemetry.Trace.Core
  ( Tracer
  , makeTracer
  , InstrumentationLibrary(..)
  , TracerOptions(..)
  , ImmutableSpan(..)
  , setGlobalTracerProvider
  , shutdownTracerProvider
  )
import OpenTelemetry.Trace
  ( createTracerProvider
  , emptyTracerProviderOptions
  )
import OpenTelemetry.Exporter.InMemory (inMemoryListExporter)

import Servant.Tower.Adapter (withTowerMiddleware)
import Servant.Tower.Middleware.Tracing (withTracingTracer)

-- ---------------------------------------------------------------------------
-- Test API
-- ---------------------------------------------------------------------------

type TestAPI =
       "ok"      :> Get '[JSON] String
  :<|> "fail500" :> Get '[JSON] String

testServer :: Server TestAPI
testServer = okHandler :<|> fail500Handler

okHandler :: Handler String
okHandler = pure "ok"

fail500Handler :: Handler String
fail500Handler = throwError err500 { errBody = "server error" }

testApp :: Application
testApp = serve (Proxy :: Proxy TestAPI) testServer

okClient :: ClientM String
fail500Client' :: ClientM String
okClient :<|> fail500Client' = client (Proxy :: Proxy TestAPI)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

withTestServer :: (Int -> IO a) -> IO a
withTestServer = testWithApplication (pure testApp)

withTestTracer :: (Tracer -> IORef [ImmutableSpan] -> IO a) -> IO a
withTestTracer action = do
  (processor, spanRef) <- inMemoryListExporter
  tp <- createTracerProvider [processor] emptyTracerProviderOptions
  setGlobalTracerProvider tp
  let tracer = makeTracer tp
        (InstrumentationLibrary
          { libraryName = "servant-tower-hs-test"
          , libraryVersion = "0.0.0"
          , librarySchemaUrl = ""
          , libraryAttributes = emptyAttributes
          })
        (TracerOptions Nothing)
  result <- action tracer spanRef
  shutdownTracerProvider tp
  pure result

runWithTracer :: Tracer -> Int -> ClientM a -> IO (Either ClientError a)
runWithTracer tracer port action = do
  manager <- newManager defaultManagerSettings
  baseUrl' <- parseBaseUrl $ "http://localhost:" ++ show port
  let env = withTowerMiddleware (withTracingTracer tracer) (mkClientEnv manager baseUrl')
  runClientM action env

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Servant tracing integration (in-memory exporter)" $ around withTestServer $ do

  it "creates a span for each request" $ \port -> withTestTracer $ \tracer spanRef -> do
    _ <- runWithTracer tracer port okClient
    threadDelay 100_000
    spans <- readIORef spanRef
    length spans `shouldSatisfy` (>= 1)

  it "sets span name to HTTP method" $ \port -> withTestTracer $ \tracer spanRef -> do
    _ <- runWithTracer tracer port okClient
    threadDelay 100_000
    spans <- readIORef spanRef
    let names = map spanName spans
    elem "GET" names `shouldBe` True

  it "records http.request.method attribute" $ \port -> withTestTracer $ \tracer spanRef -> do
    _ <- runWithTracer tracer port okClient
    threadDelay 100_000
    spans <- readIORef spanRef
    length spans `shouldSatisfy` (>= 1)
    let attrs = spanAttributes (head spans)
    lookupAttribute attrs "http.request.method" `shouldSatisfy` (/= Nothing)

  it "records http.response.status_code on success" $ \port -> withTestTracer $ \tracer spanRef -> do
    _ <- runWithTracer tracer port okClient
    threadDelay 100_000
    spans <- readIORef spanRef
    length spans `shouldSatisfy` (>= 1)
    let attrs = spanAttributes (head spans)
    lookupAttribute attrs "http.response.status_code" `shouldSatisfy` (/= Nothing)

  it "records error.type on service failure" $ \port -> withTestTracer $ \tracer spanRef -> do
    _ <- runWithTracer tracer port fail500Client'
    threadDelay 100_000
    spans <- readIORef spanRef
    length spans `shouldSatisfy` (>= 1)
    let attrs = spanAttributes (head spans)
    lookupAttribute attrs "error.type" `shouldSatisfy` (/= Nothing)
