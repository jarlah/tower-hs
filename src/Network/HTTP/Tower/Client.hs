module Network.HTTP.Tower.Client
  ( Client(..)
  , HttpResponse
  , newClient
  , newClientWith
  , runRequest
  , applyMiddleware
  , (|>)
  ) where

import Control.Exception.Safe (tryAny)
import qualified Data.ByteString.Lazy as LBS
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Concrete response type used by the client (lazy bytestring body).
type HttpResponse = HTTP.Response LBS.ByteString

-- | An HTTP client with a composable middleware stack.
data Client = Client
  { clientService :: Service HTTP.Request HttpResponse
  , clientManager :: HTTP.Manager
  }

-- | Create a client with default TLS settings.
newClient :: IO Client
newClient = newClientWith TLS.tlsManagerSettings

-- | Create a client with custom manager settings.
newClientWith :: HTTP.ManagerSettings -> IO Client
newClientWith settings = do
  mgr <- HTTP.newManager settings
  let baseService = Service $ \req -> do
        result <- tryAny $ HTTP.httpLbs req mgr
        pure $ case result of
          Left err   -> Left (HttpError err)
          Right resp -> Right resp
  pure Client
    { clientService = baseService
    , clientManager = mgr
    }

-- | Execute a request through the client's middleware stack.
runRequest :: Client -> HTTP.Request -> IO (Either ServiceError HttpResponse)
runRequest client = runService (clientService client)

-- | Apply a middleware to a client, wrapping its existing service.
applyMiddleware :: Middleware HTTP.Request HttpResponse -> Client -> Client
applyMiddleware mw client = client { clientService = mw (clientService client) }

-- | Operator for fluent middleware application.
--
-- @
-- client <- newClient
-- let configured = client
--       |> withRetry (constantBackoff 3 1.0)
--       |> withTimeout 5000
--       |> withLogging putStrLn
-- @
(|>) :: Client -> Middleware HTTP.Request HttpResponse -> Client
(|>) client mw = applyMiddleware mw client

infixl 1 |>
