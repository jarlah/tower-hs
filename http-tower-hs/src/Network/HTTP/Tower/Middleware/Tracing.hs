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
  , SpanKind(..)
  , SpanStatus(..)
  , makeTracer
  , getGlobalTracerProvider
  , addAttribute
  , setStatus
  )

import Network.HTTP.Tower.Client (HttpResponse)
import qualified Data.Version as V
import qualified Paths_http_tower_hs as Pkg

import Tower.Service (Service(..), Middleware)
import Tower.Middleware.Tracing (TracingConfig(..), defaultTracingConfig, withTracingConfig)

-- | Tracing middleware using the global TracerProvider.
-- Reads the global provider on each request (single IORef read, trivial cost).
-- If no TracerProvider is configured, this is a no-op (zero overhead).
--
-- @
-- let client' = client |> withTracing
-- @
withTracing :: Middleware HTTP.Request HttpResponse
withTracing inner = Service $ \req -> do
  tp <- getGlobalTracerProvider
  let tracer = makeTracer tp instrumentationLibrary (TracerOptions Nothing)
  runService (withTracingTracer tracer inner) req

-- | Tracing middleware using a specific Tracer.
-- Wraps each request in an OpenTelemetry span following
-- [stable HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/).
--
-- * Span name: @{method}@ (e.g., @GET@)
-- * Span kind: Client
-- * Attributes: @http.request.method@, @server.address@, @server.port@,
--   @url.full@, @http.response.status_code@, @error.type@
withTracingTracer :: Tracer -> Middleware HTTP.Request HttpResponse
withTracingTracer tracer = withTracingConfig tracer httpTracingConfig

httpTracingConfig :: TracingConfig HTTP.Request HttpResponse
httpTracingConfig = (defaultTracingConfig "")
  { tracingSpanName = decodeUtf8 . HTTP.method
  , tracingSpanKind = Client
  , tracingReqAttrs = \req s -> do
      addAttribute s "http.request.method" (decodeUtf8 (HTTP.method req))
      addAttribute s "server.address" (decodeUtf8 (HTTP.host req))
      addAttribute s "server.port" (HTTP.port req)
      addAttribute s "url.full" (buildUrl req)
  , tracingResAttrs = \resp s -> do
      let code = HTTP.statusCode (HTTP.responseStatus resp)
      addAttribute s "http.response.status_code" code
      when (code >= 400) $ do
        addAttribute s "error.type" (pack (show code))
        setStatus s (Error "HTTP error status")
  }

instrumentationLibrary :: InstrumentationLibrary
instrumentationLibrary = InstrumentationLibrary
  { libraryName = "http-tower-hs"
  , libraryVersion = pack (V.showVersion Pkg.version)
  , librarySchemaUrl = ""
  , libraryAttributes = emptyAttributes
  }

-- | Build a full URL from an http-client Request.
buildUrl :: HTTP.Request -> Text
buildUrl req =
  let scheme = if HTTP.secure req then "https" else "http" :: Text
      host = decodeUtf8 (HTTP.host req)
      port = HTTP.port req
      path = decodeUtf8 (HTTP.path req)
      query = decodeUtf8 (HTTP.queryString req)
      showPort = case (HTTP.secure req, port) of
        (True, 443)  -> ""
        (False, 80)  -> ""
        _            -> ":" <> pack (show port)
  in scheme <> "://" <> host <> showPort <> path <> query
