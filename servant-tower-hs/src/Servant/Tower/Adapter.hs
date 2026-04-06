{-# LANGUAGE DeriveAnyClass #-}

-- |
-- Module      : Servant.Tower.Adapter
-- Description : Bridge tower-hs middleware to servant's ClientMiddleware
-- License     : MIT
--
-- Adapt tower-hs middleware for use with servant-client.
--
-- @
-- import Servant.Tower.Adapter
-- import Tower.Middleware.Retry
-- import Tower.Middleware.Timeout
--
-- let env = ('withTowerMiddleware'
--              ('withRetry' ('constantBackoff' 3 1.0) . 'withTimeout' 5000))
--              (mkClientEnv manager baseUrl)
-- runClientM myApiCall env
-- @
module Servant.Tower.Adapter
  ( -- * Converting tower-hs middleware to servant ClientMiddleware
    toClientMiddleware
    -- * Error mapping
  , toClientError
  , toServiceError
    -- * Convenience
  , withTowerMiddleware
  ) where

import Control.Exception (Exception, SomeException, toException)
import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)

import Servant.Client
  ( ClientEnv(..)
  , ClientError(..)
  , ClientM
  , runClientM
  )
import Servant.Client.Core (Request, Response)
import Servant.Client.Internal.HttpClient (ClientMiddleware)

import Tower.Error (ServiceError(..))
import Tower.Service (Service(..), Middleware)

-- | Convert a tower-hs 'Middleware' (specialized to servant's Request/Response)
-- into a servant 'ClientMiddleware'.
--
-- The tower-hs middleware wraps around the servant request pipeline. Errors
-- from the tower-hs middleware are mapped to 'ClientError' via 'toClientError'.
--
-- @
-- toClientMiddleware (withRetry (constantBackoff 3 1.0))
-- @
toClientMiddleware :: Middleware Request Response -> ClientMiddleware
toClientMiddleware towerMw servantApp req = do
  env <- ask
  let wrappedService = Service $ \r -> do
        result <- runClientM (servantApp r) env
        case result of
          Left clientErr -> pure (Left (toServiceError clientErr))
          Right resp     -> pure (Right resp)
      Service towered = towerMw wrappedService
  result <- liftIO (towered req)
  case result of
    Left svcErr -> throwError (toClientError svcErr)
    Right resp  -> pure resp

-- | Map a tower-hs 'ServiceError' to a servant 'ClientError'.
toClientError :: ServiceError -> ClientError
toClientError (TransportError e)    = ConnectionError e
toClientError TimeoutError          = ConnectionError (toException TimeoutEx)
toClientError CircuitBreakerOpen    = ConnectionError (toException CircuitBreakerEx)
toClientError (RetryExhausted _ e)  = toClientError e
toClientError (CustomError t)       = ConnectionError (toException (userError (show t)))

-- | Map a servant 'ClientError' to a tower-hs 'ServiceError'.
toServiceError :: ClientError -> ServiceError
toServiceError (ConnectionError e) = TransportError e
toServiceError e                   = TransportError (toException e)

-- | Apply tower-hs middleware to a servant 'ClientEnv'.
--
-- @
-- let env' = withTowerMiddleware (withRetry (constantBackoff 3 1.0)) env
-- runClientM myApiCall env'
-- @
withTowerMiddleware :: Middleware Request Response -> ClientEnv -> ClientEnv
withTowerMiddleware towerMw env =
  env { middleware = toClientMiddleware towerMw . middleware env }

-- Internal exception types for servant error mapping

data TimeoutEx = TimeoutEx
  deriving (Show, Exception)

data CircuitBreakerEx = CircuitBreakerEx
  deriving (Show, Exception)
