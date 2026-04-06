{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Servant.Tower.Middleware.Tracing
-- Description : OpenTelemetry tracing for servant requests
-- License     : MIT
module Servant.Tower.Middleware.Tracing
  ( withTracing
  , withTracingTracer
  , servantTracingConfig
  ) where

import Control.Monad (when)
import Data.Text (Text, pack)
import Data.Text.Encoding (decodeUtf8)
import qualified Data.Version as V
import Network.HTTP.Types.Status (statusCode)
import qualified Paths_servant_tower_hs as Pkg

import OpenTelemetry.Attributes (emptyAttributes)
import OpenTelemetry.Trace.Core
  ( Tracer
  , InstrumentationLibrary(..)
  , TracerOptions(..)
  , SpanKind(..)
  , SpanStatus(..)
  , makeTracer
  , getGlobalTracerProvider
  , addAttribute
  , setStatus
  )

import Servant.Client.Core (Request, Response, requestMethod, responseStatusCode)
import Tower.Service (Service(..), Middleware)
import Tower.Middleware.Tracing (TracingConfig(..), defaultTracingConfig, withTracingConfig)

-- | Tracing middleware using the global TracerProvider.
withTracing :: Middleware Request Response
withTracing inner = Service $ \req -> do
  tp <- getGlobalTracerProvider
  let tracer = makeTracer tp instrumentationLibrary (TracerOptions Nothing)
  runService (withTracingTracer tracer inner) req

-- | Tracing middleware using a specific Tracer.
withTracingTracer :: Tracer -> Middleware Request Response
withTracingTracer tracer = withTracingConfig tracer servantTracingConfig

-- | Tracing config with HTTP semantic conventions for servant types.
servantTracingConfig :: TracingConfig Request Response
servantTracingConfig = (defaultTracingConfig "")
  { tracingSpanName = decodeUtf8 . requestMethod
  , tracingSpanKind = Client
  , tracingReqAttrs = \req s -> do
      addAttribute s "http.request.method" (decodeUtf8 (requestMethod req))
  , tracingResAttrs = \resp s -> do
      let code = statusCode (responseStatusCode resp)
      addAttribute s "http.response.status_code" code
      when (code >= 400) $ do
        addAttribute s "error.type" (pack (show code))
        setStatus s (Error "HTTP error status")
  }

instrumentationLibrary :: InstrumentationLibrary
instrumentationLibrary = InstrumentationLibrary
  { libraryName = "servant-tower-hs"
  , libraryVersion = pack (V.showVersion Pkg.version)
  , librarySchemaUrl = ""
  , libraryAttributes = emptyAttributes
  }
