{-# LANGUAGE OverloadedStrings #-}

module Network.HTTP.Tower.Middleware.Tracing
  ( withTracing
  , withTracingTracer
  ) where

import Control.Monad (when)
import Data.Text (Text, pack)
import Data.Text.Encoding (decodeUtf8)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types.Status as HTTP

import OpenTelemetry.Attributes (emptyAttributes)
import OpenTelemetry.Trace.Core
  ( Tracer
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

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError, displayError)

-- | Tracing middleware using the global TracerProvider.
-- Creates a span for each HTTP request with standard HTTP semantic attributes.
-- If no TracerProvider is configured, this is a no-op (zero overhead).
withTracing :: IO (Middleware HTTP.Request HttpResponse)
withTracing = do
  tp <- getGlobalTracerProvider
  let tracer = makeTracer tp
        (InstrumentationLibrary
          { libraryName = "http-tower-hs"
          , libraryVersion = "0.1.0.0"
          , librarySchemaUrl = ""
          , libraryAttributes = emptyAttributes
          })
        (TracerOptions Nothing)
  pure (withTracingTracer tracer)

-- | Tracing middleware using a specific Tracer.
-- Wraps each request in an OpenTelemetry span with:
--
-- * Span name: @HTTP {method} {host}@
-- * Span kind: Client
-- * Attributes: @http.method@, @http.host@, @http.path@, @http.scheme@, @http.status_code@
-- * Error status on failure or HTTP 4xx/5xx
withTracingTracer :: Tracer -> Middleware HTTP.Request HttpResponse
withTracingTracer tracer inner = Service $ \req -> do
  let spanName = decodeUtf8 (HTTP.method req) <> " " <> decodeUtf8 (HTTP.host req)
      spanArgs = defaultSpanArguments { kind = Client }
  inSpan' tracer spanName spanArgs $ \s -> do
    addAttribute s "http.method" (decodeUtf8 (HTTP.method req))
    addAttribute s "http.host" (decodeUtf8 (HTTP.host req))
    addAttribute s "http.path" (decodeUtf8 (HTTP.path req))
    addAttribute s "http.scheme" (if HTTP.secure req then "https" else "http" :: Text)
    addAttribute s "net.peer.port" (pack (show (HTTP.port req)))

    result <- runService inner req

    case result of
      Right resp -> do
        let code = HTTP.statusCode (HTTP.responseStatus resp)
        addAttribute s "http.status_code" code
        when (code >= 400) $
          setStatus s (Error "HTTP error status")
        pure (Right resp)
      Left err -> do
        setStatus s (Error (displayError err))
        pure (Left err)
