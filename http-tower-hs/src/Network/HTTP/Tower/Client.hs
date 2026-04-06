-- |
-- Module      : Network.HTTP.Tower.Client
-- Description : HTTP client with composable middleware
-- License     : MIT
--
-- Create an HTTP client and compose middleware using the @('|>')@ operator:
--
-- @
-- client <- 'newClient'
-- let configured = client
--       '|>' withRetry (constantBackoff 3 1.0)
--       '|>' withTimeout 5000
-- result <- 'runRequest' configured request
-- @
--
-- For mTLS (client certificate authentication):
--
-- @
-- client <- 'newClientWithTLS'
--   (Just \"certs\/ca.pem\")
--   (Just (\"certs\/client.pem\", \"certs\/client-key.pem\"))
-- @
module Network.HTTP.Tower.Client
  ( Client(..)
  , HttpResponse
  , newClient
  , newClientWith
  , newClientWithTLS
  , runRequest
  , applyMiddleware
  , (|>)
  ) where

import Control.Exception.Safe (tryAny)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.X509.CertificateStore as X509
import qualified Network.Connection as Conn
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS
import qualified Network.TLS as TLS.Core
import qualified Network.TLS.Extra.Cipher as TLS.Cipher
import qualified System.X509 as X509System

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError(..))

-- | Concrete response type used by the client (lazy bytestring body).
type HttpResponse = HTTP.Response LBS.ByteString

-- | An HTTP client with a composable middleware stack.
data Client = Client
  { clientService :: Service HTTP.Request HttpResponse
    -- ^ The service with all middleware applied.
  , clientManager :: HTTP.Manager
    -- ^ The underlying connection manager.
  }

-- | Create a client with default TLS settings. HTTPS works out of the box.
newClient :: IO Client
newClient = newClientWith TLS.tlsManagerSettings

-- | Create a client with custom manager settings.
--
-- Use this with 'Network.HTTP.Client.TLS.mkManagerSettings' for advanced
-- TLS configuration, proxies, etc.
newClientWith :: HTTP.ManagerSettings -> IO Client
newClientWith settings = do
  mgr <- HTTP.newManager settings
  let baseService = Service $ \req -> do
        result <- tryAny $ HTTP.httpLbs req mgr
        pure $ case result of
          Left err   -> Left (TransportError err)
          Right resp -> Right resp
  pure Client
    { clientService = baseService
    , clientManager = mgr
    }

-- | Create a client with custom TLS certificate configuration.
--
-- Supports:
--
-- * Custom CA bundle for server certificate verification
-- * Client certificate authentication (mTLS)
-- * Both, either, or neither
--
-- @
-- -- Custom CA only (verify server against your own CA)
-- client <- 'newClientWithTLS' (Just \"certs\/ca.pem\") Nothing
--
-- -- mTLS (client cert + custom CA)
-- client <- 'newClientWithTLS'
--   (Just \"certs\/ca.pem\")
--   (Just (\"certs\/client.pem\", \"certs\/client-key.pem\"))
--
-- -- mTLS with system CA store
-- client <- 'newClientWithTLS'
--   Nothing
--   (Just (\"certs\/client.pem\", \"certs\/client-key.pem\"))
-- @
newClientWithTLS
  :: Maybe FilePath                    -- ^ Path to CA certificate (PEM). 'Nothing' uses system store.
  -> Maybe (FilePath, FilePath)        -- ^ Client cert and key paths (PEM) for mTLS. 'Nothing' for no client cert.
  -> IO Client
newClientWithTLS mCaPath mClientCert = do
  -- Load CA store
  caStore <- case mCaPath of
    Just caPath -> do
      mStore <- X509.readCertificateStore caPath
      case mStore of
        Just store -> pure store
        Nothing    -> fail $ "Failed to load CA certificate: " <> caPath
    Nothing -> X509System.getSystemCertificateStore

  -- Load client credentials
  credentials <- case mClientCert of
    Just (certPath, keyPath) -> do
      result <- TLS.Core.credentialLoadX509 certPath keyPath
      case result of
        Right cred -> pure (TLS.Core.Credentials [cred])
        Left err   -> fail $ "Failed to load client certificate: " <> err
    Nothing -> pure (TLS.Core.Credentials [])

  let defaults = TLS.Core.defaultParamsClient "" mempty
      clientParams = defaults
        { TLS.Core.clientShared = (TLS.Core.clientShared defaults)
            { TLS.Core.sharedCAStore      = caStore
            , TLS.Core.sharedCredentials  = credentials
            }
        , TLS.Core.clientSupported = (TLS.Core.clientSupported defaults)
            { TLS.Core.supportedCiphers = TLS.Cipher.ciphersuite_default
            }
        , TLS.Core.clientHooks = (TLS.Core.clientHooks defaults)
            { TLS.Core.onCertificateRequest = \_ ->
                case credentials of
                  TLS.Core.Credentials (cred:_) -> pure (Just cred)
                  _                             -> pure Nothing
            }
        }
      tlsSettings = Conn.TLSSettings clientParams
      managerSettings = TLS.mkManagerSettings tlsSettings Nothing

  newClientWith managerSettings

-- | Execute a request through the client's middleware stack.
runRequest :: Client -> HTTP.Request -> IO (Either ServiceError HttpResponse)
runRequest client = runService (clientService client)

-- | Apply a middleware to a client, wrapping its existing service.
applyMiddleware :: Middleware HTTP.Request HttpResponse -> Client -> Client
applyMiddleware mw client = client { clientService = mw (clientService client) }

-- | Operator for fluent middleware application.
--
-- @
-- client <- 'newClient'
-- let configured = client
--       '|>' withRetry (constantBackoff 3 1.0)
--       '|>' withTimeout 5000
--       '|>' withLogging putStrLn
-- @
(|>) :: Client -> Middleware HTTP.Request HttpResponse -> Client
(|>) client mw = applyMiddleware mw client

infixl 1 |>
