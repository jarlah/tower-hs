module Network.HTTP.Tower.Middleware.CircuitBreaker
  ( CircuitBreakerConfig(..)
  , CircuitBreakerState(..)
  , CircuitBreaker
  , newCircuitBreaker
  , withCircuitBreaker
  , getCircuitBreakerState
  ) where

import Control.Concurrent.STM
import Data.Time.Clock (UTCTime, NominalDiffTime, getCurrentTime, diffUTCTime)

import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Configuration for the circuit breaker.
data CircuitBreakerConfig = CircuitBreakerConfig
  { cbFailureThreshold :: !Int
    -- ^ Number of consecutive failures before the breaker trips open.
  , cbCooldownPeriod   :: !NominalDiffTime
    -- ^ How long to stay open before transitioning to half-open.
  } deriving (Show, Eq)

-- | Observable state of the circuit breaker.
data CircuitBreakerState
  = Closed      -- ^ Normal operation, requests flow through.
  | Open        -- ^ Tripped — all requests rejected immediately.
  | HalfOpen    -- ^ Testing — one request allowed through to probe recovery.
  deriving (Show, Eq)

-- | Internal mutable state, managed via STM.
data BreakerInternals = BreakerInternals
  { biState          :: !CircuitBreakerState
  , biFailureCount   :: !Int
  , biLastFailureAt  :: !(Maybe UTCTime)
  }

-- | Opaque handle to a circuit breaker instance.
-- Create with 'newCircuitBreaker', share across requests.
newtype CircuitBreaker = CircuitBreaker (TVar BreakerInternals)

-- | Create a new circuit breaker in the Closed state.
newCircuitBreaker :: IO CircuitBreaker
newCircuitBreaker = CircuitBreaker <$> newTVarIO BreakerInternals
  { biState         = Closed
  , biFailureCount  = 0
  , biLastFailureAt = Nothing
  }

-- | Read the current state of the circuit breaker.
getCircuitBreakerState :: CircuitBreaker -> IO CircuitBreakerState
getCircuitBreakerState (CircuitBreaker var) = biState <$> readTVarIO var

-- | Circuit breaker middleware.
--
-- * **Closed**: requests pass through. On failure, increment the failure
--   counter. When the counter reaches the threshold, trip to Open.
--
-- * **Open**: all requests are immediately rejected with 'CircuitBreakerOpen'.
--   After the cooldown period elapses, transition to HalfOpen.
--
-- * **HalfOpen**: allow exactly one request through. If it succeeds, reset
--   to Closed. If it fails, trip back to Open.
--
-- The 'CircuitBreaker' handle is shared across all requests, so create it
-- once and reuse it:
--
-- @
-- breaker <- newCircuitBreaker
-- let client' = client |> withCircuitBreaker config breaker
-- @
withCircuitBreaker :: CircuitBreakerConfig -> CircuitBreaker -> Middleware req res
withCircuitBreaker config (CircuitBreaker var) inner = Service $ \req -> do
  now <- getCurrentTime
  decision <- atomically $ do
    internals <- readTVar var
    case biState internals of
      Open ->
        case biLastFailureAt internals of
          Just lastFail
            | diffUTCTime now lastFail >= cbCooldownPeriod config -> do
                writeTVar var internals { biState = HalfOpen }
                pure AllowRequest
          _ -> pure RejectRequest
      HalfOpen -> pure AllowRequest
      Closed   -> pure AllowRequest

  case decision of
    RejectRequest -> pure (Left CircuitBreakerOpen)
    AllowRequest  -> do
      result <- runService inner req
      now' <- getCurrentTime
      atomically $ do
        internals <- readTVar var
        case result of
          Right _ -> writeTVar var BreakerInternals
            { biState         = Closed
            , biFailureCount  = 0
            , biLastFailureAt = Nothing
            }
          Left _ ->
            case biState internals of
              HalfOpen -> writeTVar var BreakerInternals
                { biState         = Open
                , biFailureCount  = cbFailureThreshold config
                , biLastFailureAt = Just now'
                }
              _ -> do
                let newCount = biFailureCount internals + 1
                if newCount >= cbFailureThreshold config
                  then writeTVar var BreakerInternals
                    { biState         = Open
                    , biFailureCount  = newCount
                    , biLastFailureAt = Just now'
                    }
                  else writeTVar var internals
                    { biFailureCount  = newCount
                    , biLastFailureAt = Just now'
                    }
      pure result

data Decision = AllowRequest | RejectRequest
