-- |
-- Module      : Tower.Middleware.CircuitBreaker
-- Description : Three-state circuit breaker using STM
-- License     : MIT
--
-- Prevents cascading failures by tracking consecutive errors and
-- short-circuiting requests when a service is known to be down.
--
-- @
-- breaker <- 'newCircuitBreaker'
-- let config = 'CircuitBreakerConfig' { 'cbFailureThreshold' = 5, 'cbCooldownPeriod' = 30 }
-- @
--
-- == State machine
--
-- * __Closed__ — normal operation. Failures are counted. Trips to Open
--   after reaching the threshold.
-- * __Open__ — all requests rejected with 'CircuitBreakerOpen'. After the
--   cooldown period, transitions to HalfOpen.
-- * __HalfOpen__ — one probe request is allowed through. Success resets to
--   Closed; failure trips back to Open.
module Tower.Middleware.CircuitBreaker
  ( CircuitBreakerConfig(..)
  , CircuitBreakerState(..)
  , CircuitBreaker
  , newCircuitBreaker
  , withCircuitBreaker
  , getCircuitBreakerState
  ) where

import Control.Concurrent.STM
import Data.Time.Clock (UTCTime, NominalDiffTime, getCurrentTime, diffUTCTime)

import Tower.Service (Service(..), Middleware)
import Tower.Error (ServiceError(..))

-- | Configuration for the circuit breaker.
data CircuitBreakerConfig = CircuitBreakerConfig
  { cbFailureThreshold :: !Int
    -- ^ Number of consecutive failures before the breaker trips open.
  , cbCooldownPeriod   :: !NominalDiffTime
    -- ^ How long to stay open before transitioning to half-open (in seconds).
  } deriving (Show, Eq)

-- | Observable state of the circuit breaker.
data CircuitBreakerState
  = Closed      -- ^ Normal operation, requests flow through.
  | Open        -- ^ Tripped — all requests rejected immediately.
  | HalfOpen    -- ^ Testing — one request allowed through to probe recovery.
  deriving (Show, Eq)

data BreakerInternals = BreakerInternals
  { biState          :: !CircuitBreakerState
  , biFailureCount   :: !Int
  , biLastFailureAt  :: !(Maybe UTCTime)
  }

-- | Opaque handle to a circuit breaker instance.
-- Create with 'newCircuitBreaker', share across requests.
newtype CircuitBreaker = CircuitBreaker (TVar BreakerInternals)

-- | Create a new circuit breaker in the 'Closed' state.
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
-- The 'CircuitBreaker' handle is shared across all requests — create it
-- once and reuse it:
--
-- @
-- breaker <- 'newCircuitBreaker'
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
