{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Tower.Middleware.Tracing
-- Description : Generic OpenTelemetry tracing middleware
-- License     : MIT
--
-- Wraps each service call in an OpenTelemetry span. Users provide a
-- 'TracingConfig' to control the span name, kind, and attribute extraction.
--
-- @
-- let config = ('defaultTracingConfig' "my-service")
--       { 'tracingReqAttrs' = \\req s -> addAttribute s "my.attr" (show req) }
-- client |> 'withTracingConfig' tracer config
-- @
module Tower.Middleware.Tracing
  ( TracingConfig(..)
  , defaultTracingConfig
  , withTracingConfig
  , withTracingGlobal
  ) where

import Data.Text (Text)

import OpenTelemetry.Attributes (emptyAttributes)
import OpenTelemetry.Trace.Core
  ( Tracer
  , Span
  , InstrumentationLibrary(..)
  , TracerOptions(..)
  , SpanArguments(..)
  , SpanKind(..)
  , SpanStatus(..)
  , makeTracer
  , getGlobalTracerProvider
  , defaultSpanArguments
  , addAttribute
  , setStatus
  , inSpan'
  )

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError, displayError)

-- | Configuration for the generic tracing middleware.
data TracingConfig req res = TracingConfig
  { tracingSpanName :: req -> Text
    -- ^ Derive the span name from the request.
  , tracingSpanKind :: SpanKind
    -- ^ The span kind (e.g., 'Client', 'Server', 'Internal').
  , tracingReqAttrs :: req -> Span -> IO ()
    -- ^ Add request attributes to the span before the call.
  , tracingResAttrs :: res -> Span -> IO ()
    -- ^ Add response attributes to the span after a successful call.
  , tracingErrAttrs :: ServiceError -> Span -> IO ()
    -- ^ Add error attributes to the span on failure (in addition to setting error status).
  }

-- | Default tracing config: fixed span name, 'Client' kind, no attributes.
-- On error, adds @error.type@ attribute with the error description.
defaultTracingConfig :: Text -> TracingConfig req res
defaultTracingConfig name = TracingConfig
  { tracingSpanName = const name
  , tracingSpanKind = Client
  , tracingReqAttrs = \_ _ -> pure ()
  , tracingResAttrs = \_ _ -> pure ()
  , tracingErrAttrs = \err s -> addAttribute s "error.type" (displayError err)
  }

-- | Tracing middleware using a specific 'Tracer' and 'TracingConfig'.
--
-- Wraps each service call in an OpenTelemetry span. On success, calls
-- 'tracingResAttrs' to record response attributes. On failure, sets
-- the span status to error with the 'ServiceError' description.
withTracingConfig :: Tracer -> TracingConfig req res -> Middleware req res
withTracingConfig tracer config inner = Service $ \req -> do
  let spanName = tracingSpanName config req
      spanArgs = defaultSpanArguments { kind = tracingSpanKind config }
  inSpan' tracer spanName spanArgs $ \s -> do
    tracingReqAttrs config req s
    result <- runService inner req
    case result of
      Right res -> do
        tracingResAttrs config res s
        pure (Right res)
      Left err -> do
        tracingErrAttrs config err s
        setStatus s (Error (displayError err))
        pure (Left err)

-- | Tracing middleware using the global 'TracerProvider'.
--
-- Reads the global provider on each request (single IORef read, trivial cost).
-- If no TracerProvider is configured, this is a no-op.
withTracingGlobal :: InstrumentationLibrary -> TracingConfig req res -> Middleware req res
withTracingGlobal lib config inner = Service $ \req -> do
  tp <- getGlobalTracerProvider
  let tracer = makeTracer tp lib (TracerOptions Nothing)
  runService (withTracingConfig tracer config inner) req
