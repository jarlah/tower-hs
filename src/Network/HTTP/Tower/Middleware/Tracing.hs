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
withTracingTracer tracer inner = Service $ \req -> do
  let spanName = decodeUtf8 (HTTP.method req)
      spanArgs = defaultSpanArguments { kind = Client }
  inSpan' tracer spanName spanArgs $ \s -> do
    -- Required attributes
    addAttribute s "http.request.method" (decodeUtf8 (HTTP.method req))
    addAttribute s "server.address" (decodeUtf8 (HTTP.host req))
    addAttribute s "server.port" (HTTP.port req)
    addAttribute s "url.full" (buildUrl req)

    result <- runService inner req

    case result of
      Right resp -> do
        let code = HTTP.statusCode (HTTP.responseStatus resp)
        addAttribute s "http.response.status_code" code
        when (code >= 400) $ do
          addAttribute s "error.type" (pack (show code))
          setStatus s (Error "HTTP error status")
        pure (Right resp)
      Left err -> do
        addAttribute s "error.type" (displayError err)
        setStatus s (Error (displayError err))
        pure (Left err)

instrumentationLibrary :: InstrumentationLibrary
instrumentationLibrary = InstrumentationLibrary
  { libraryName = "http-tower-hs"
  , libraryVersion = "0.1.0.0"
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
