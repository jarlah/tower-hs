{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE NamedFieldPuns #-}

module Network.HTTP.Tower.Middleware.TracingDockerSpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Data.Aeson (Value(..), (.:), decode, withObject)
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Vector as V
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.Internal as HTTP
import qualified Network.HTTP.Client.TLS as TLS
import qualified Network.HTTP.Types as HTTP
import System.Environment (setEnv, unsetEnv)
import System.Process (readProcess)
import Test.Hspec

import qualified TestContainers as TC
import TestContainers.Hspec (withContainers)

import OpenTelemetry.Trace.Core
  ( makeTracer
  , InstrumentationLibrary(..)
  , TracerOptions(..)
  , shutdownTracerProvider
  )
import OpenTelemetry.Attributes (emptyAttributes)
import OpenTelemetry.Trace (initializeGlobalTracerProvider)

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core
import Network.HTTP.Tower.Middleware.Tracing

-- | Jaeger container setup via testcontainers.
data JaegerPorts = JaegerPorts
  { otlpPort   :: Int
  , jaegerPort :: Int
  }

setupJaeger :: TC.TestContainer JaegerPorts
setupJaeger = do
  container <- TC.run $ TC.containerRequest (TC.fromTag "jaegertracing/all-in-one:latest")
    TC.& TC.setExpose [4318, 16686]
    TC.& TC.setWaitingFor (TC.waitUntilTimeout 60 (TC.waitUntilMappedPortReachable 16686))
  pure JaegerPorts
    { otlpPort   = TC.containerPort container 4318
    , jaegerPort = TC.containerPort container 16686
    }

dockerAvailable :: IO Bool
dockerAvailable = do
  result <- try (readProcess "docker" ["info"] "") :: IO (Either SomeException String)
  pure $ case result of
    Right _ -> True
    Left _  -> False

queryJaegerTraces :: HTTP.Manager -> Int -> String -> IO (Maybe Value)
queryJaegerTraces mgr port service = do
  req <- HTTP.parseRequest $
    "http://localhost:" <> show port <> "/api/traces?service=" <> service <> "&limit=10"
  resp <- HTTP.httpLbs req mgr
  pure (decode (HTTP.responseBody resp))

spec :: Spec
spec = describe "Tracing Docker integration (Jaeger via testcontainers)" $ beforeAll dockerAvailable $ do

  it "exports spans to Jaeger via OTLP" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available, skipping Jaeger integration test"
      else withContainers setupJaeger $ \JaegerPorts{otlpPort, jaegerPort} -> do
        -- Configure OTel SDK via environment variables
        setEnv "OTEL_EXPORTER_OTLP_ENDPOINT" ("http://localhost:" <> show otlpPort)
        setEnv "OTEL_EXPORTER_OTLP_PROTOCOL" "http/protobuf"
        setEnv "OTEL_SERVICE_NAME" "http-tower-hs-tc-test"

        -- Initialize TracerProvider from env
        tp <- initializeGlobalTracerProvider

        let tracer = makeTracer tp
              (InstrumentationLibrary
                { libraryName = "http-tower-hs-tc-test"
                , libraryVersion = "0.1.0.0"
                , librarySchemaUrl = ""
                , libraryAttributes = emptyAttributes
                })
              (TracerOptions Nothing)

        -- Run a request through the tracing middleware
        let svc = Service $ \_ -> pure (Right fakeResponse)
            traced = withTracingTracer tracer svc
        req <- HTTP.parseRequest "http://example.com/testcontainers-test"
        _ <- runService traced req

        -- Shut down to flush all spans
        shutdownTracerProvider tp

        -- Clean up env vars
        unsetEnv "OTEL_EXPORTER_OTLP_ENDPOINT"
        unsetEnv "OTEL_EXPORTER_OTLP_PROTOCOL"
        unsetEnv "OTEL_SERVICE_NAME"

        -- Give Jaeger time to index
        threadDelay 3_000_000

        -- Query Jaeger for our traces
        mgr <- HTTP.newManager TLS.tlsManagerSettings
        result <- queryJaegerTraces mgr jaegerPort "http-tower-hs-tc-test"
        case result of
          Nothing -> expectationFailure "Failed to parse Jaeger API response"
          Just val -> do
            let traceCount = parseMaybe (withObject "resp" $ \o -> do
                    arr <- o .: "data"
                    pure (V.length (arr :: V.Vector Value))) val
            case traceCount of
              Just n  -> n `shouldSatisfy` (>= 1)
              Nothing -> expectationFailure $ "Unexpected Jaeger response: " ++ show val

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
