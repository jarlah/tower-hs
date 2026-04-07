{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Servant.Tower.IntegrationSpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (newTVarIO, readTVar, TVar, modifyTVar', atomically)
import Control.Monad.IO.Class (liftIO)
import Data.Function ((&))
import Data.IORef
import Data.Proxy (Proxy(..))
import Data.Text (Text, isInfixOf)
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Network.Wai.Handler.Warp (testWithApplication)
import Servant
import Servant.Client
import Test.Hspec

import Servant.Tower.Adapter (withTowerMiddleware)
import qualified Servant.Tower.Middleware.Logging as STL
import qualified Servant.Tower.Middleware.SetHeader as STS
import qualified Servant.Tower.Middleware.Validate as STV
import Tower.Middleware.CircuitBreaker
import Tower.Middleware.Filter
import Tower.Middleware.Hedge
import qualified Tower.Middleware.Logging as TL
import qualified Tower.Middleware.Tracing
import Tower.Middleware.Retry
import Tower.Middleware.Timeout

import OpenTelemetry.Attributes (emptyAttributes)
import OpenTelemetry.Trace.Core (InstrumentationLibrary(..))

-- ---------------------------------------------------------------------------
-- Test API
-- ---------------------------------------------------------------------------

type TestAPI =
       "hello"   :> Get '[JSON] String
  :<|> "slow"    :> Get '[JSON] String
  :<|> "flaky"   :> Get '[JSON] String
  :<|> "fail500" :> Get '[JSON] String

testServer :: TVar Int -> Server TestAPI
testServer callCount =
       helloHandler
  :<|> slowHandler
  :<|> flakyHandler callCount
  :<|> fail500Handler

helloHandler :: Handler String
helloHandler = pure "hello"

slowHandler :: Handler String
slowHandler = do
  liftIO $ threadDelay 2_000_000 -- 2 seconds
  pure "slow"

flakyHandler :: TVar Int -> Handler String
flakyHandler callCount = do
  n <- liftIO $ atomically $ do
    modifyTVar' callCount (+ 1)
    readTVar callCount
  if n <= 2
    then throwError err500 { errBody = "flaky failure" }
    else pure "recovered"

fail500Handler :: Handler String
fail500Handler = throwError err500 { errBody = "always fails" }

testApp :: TVar Int -> Application
testApp callCount = serve (Proxy :: Proxy TestAPI) (testServer callCount)

-- ---------------------------------------------------------------------------
-- Client functions
-- ---------------------------------------------------------------------------

helloClient :: ClientM String
slowClient :: ClientM String
flakyClient :: ClientM String
fail500Client :: ClientM String
helloClient :<|> slowClient :<|> flakyClient :<|> fail500Client =
  client (Proxy :: Proxy TestAPI)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

withTestServer :: (Int -> IO a) -> IO a
withTestServer action = do
  callCount <- newTVarIO 0
  testWithApplication (pure (testApp callCount)) action

runWithMiddleware :: Int -> ClientM a -> (ClientEnv -> ClientEnv) -> IO (Either ClientError a)
runWithMiddleware port action applyMw = do
  manager <- newManager defaultManagerSettings
  baseUrl' <- parseBaseUrl $ "http://localhost:" ++ show port
  let env = mkClientEnv manager baseUrl' & applyMw
  runClientM action env

runPlain :: Int -> ClientM a -> IO (Either ClientError a)
runPlain port action = runWithMiddleware port action id

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Servant.Tower integration" $ around withTestServer $ do

  -- Baseline: middleware adapter does not break normal requests
  describe "baseline (no middleware)" $ do
    it "calls a simple endpoint" $ \port -> do
      result <- runPlain port helloClient
      result `shouldBe` Right "hello"

  -- Retry middleware
  describe "withRetry" $ do
    it "retries flaky endpoint and eventually succeeds" $ \port -> do
      result <- runWithMiddleware port flakyClient $
        withTowerMiddleware (withRetry (constantBackoff 3 0))
      result `shouldBe` Right "recovered"

    it "exhausts retries on permanently failing endpoint" $ \port -> do
      result <- runWithMiddleware port fail500Client $
        withTowerMiddleware (withRetry (constantBackoff 2 0))
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected failure after retry exhaustion"

  -- Timeout middleware
  describe "withTimeout" $ do
    it "passes fast requests through" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (withTimeout 5000)
      result `shouldBe` Right "hello"

    it "times out slow requests" $ \port -> do
      result <- runWithMiddleware port slowClient $
        withTowerMiddleware (withTimeout 500) -- 500ms, server takes 2s
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected timeout error"

  -- Circuit breaker middleware
  describe "withCircuitBreaker" $ do
    it "trips open after repeated failures and rejects fast" $ \port -> do
      breaker <- newCircuitBreaker
      let config = CircuitBreakerConfig { cbFailureThreshold = 2, cbCooldownPeriod = 10 }
          mw = withTowerMiddleware (withCircuitBreaker config breaker)

      -- Two failures trip the breaker
      _ <- runWithMiddleware port fail500Client mw
      _ <- runWithMiddleware port fail500Client mw
      getCircuitBreakerState breaker >>= (`shouldBe` Open)

      -- Third call should be rejected immediately by circuit breaker
      result <- runWithMiddleware port fail500Client mw
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected circuit breaker rejection"

  -- Composed middleware stack
  describe "composed middleware" $ do
    it "retry + timeout works together on fast endpoint" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware
          ( withRetry (constantBackoff 2 0)
          . withTimeout 5000
          )
      result `shouldBe` Right "hello"

    it "timeout fires before retry can succeed on slow endpoint" $ \port -> do
      result <- runWithMiddleware port slowClient $
        withTowerMiddleware
          ( withRetry (constantBackoff 2 0)
          . withTimeout 500
          )
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected timeout through retry"

    it "retry + circuit breaker compose correctly" $ \port -> do
      breaker <- newCircuitBreaker
      let config = CircuitBreakerConfig { cbFailureThreshold = 5, cbCooldownPeriod = 10 }
      result <- runWithMiddleware port flakyClient $
        withTowerMiddleware
          ( withRetry (constantBackoff 3 0)
          . withCircuitBreaker config breaker
          )
      result `shouldBe` Right "recovered"
      -- Breaker should be closed since it recovered
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)

  -- Filter middleware
  describe "withFilter" $ do
    it "passes requests that match the predicate" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (withFilter (const True))
      result `shouldBe` Right "hello"

    it "rejects requests that don't match the predicate" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (withFilter (const False))
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected filter rejection"

  -- Hedge middleware
  describe "withHedge" $ do
    it "returns result for fast endpoint" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (withHedge 500)
      result `shouldBe` Right "hello"

  -- Full middleware stack: generic + servant-specific combined
  describe "full middleware stack" $ do
    it "composes generic tower-hs and servant-specific middleware together" $ \port -> do
      logRef <- newIORef ([] :: [Text])
      breaker <- newCircuitBreaker
      let config = CircuitBreakerConfig { cbFailureThreshold = 10, cbCooldownPeriod = 30 }
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware
          ( -- Generic tower-hs middleware
            withRetry (exponentialBackoff 2 0.1 2.0)
          . withTimeout 5000
          . withCircuitBreaker config breaker
          -- Servant-specific middleware
          . STS.withBearerAuth "my-token"
          . STS.withUserAgent "test-agent/1.0"
          . STS.withHeader "X-Custom" "value"
          . STV.withValidateStatus (\c -> c >= 200 && c < 300)
          . STL.withLogging (\msg -> modifyIORef' logRef (msg :))
          )
      result `shouldBe` Right "hello"
      getCircuitBreakerState breaker >>= (`shouldBe` Closed)
      -- Verify logging happened
      logs <- readIORef logRef
      length logs `shouldBe` 1

  -- -----------------------------------------------------------------------
  -- Servant-specific middleware
  -- -----------------------------------------------------------------------

  -- SetHeader middleware
  describe "Servant.Tower.Middleware.SetHeader" $ do
    it "adds headers without breaking requests" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware
          ( STS.withBearerAuth "my-token"
          . STS.withUserAgent "test-agent/1.0"
          . STS.withHeader "X-Custom" "value"
          )
      result `shouldBe` Right "hello"

  -- Validate middleware
  describe "Servant.Tower.Middleware.Validate" $ do
    it "passes valid status codes" $ \port -> do
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (STV.withValidateStatus (\c -> c >= 200 && c < 300))
      result `shouldBe` Right "hello"

    it "rejects invalid status codes" $ \port -> do
      result <- runWithMiddleware port fail500Client $
        withTowerMiddleware (STV.withValidateStatus (\c -> c >= 200 && c < 300))
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected validation failure"

  -- Logging middleware
  describe "Servant.Tower.Middleware.Logging" $ do
    it "logs successful requests" $ \port -> do
      logRef <- newIORef ([] :: [Text])
      let logger msg = modifyIORef' logRef (msg :)
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (STL.withLogging logger)
      result `shouldBe` Right "hello"
      logs <- readIORef logRef
      length logs `shouldBe` 1
      isInfixOf "GET" (head logs) `shouldBe` True

    it "logs with generic formatter" $ \port -> do
      logRef <- newIORef ([] :: [Text])
      let logger msg = modifyIORef' logRef (msg :)
          formatter _ _ _ = "custom-log"
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware (TL.withLogging formatter logger)
      result `shouldBe` Right "hello"
      logs <- readIORef logRef
      head logs `shouldBe` "custom-log"

  -- Tracing middleware (no-op without SDK, but must be transparent)
  describe "Servant.Tower.Middleware.Tracing" $ do
    it "passes requests through transparently" $ \port -> do
      -- Import locally to avoid name clash
      result <- runWithMiddleware port helloClient $
        withTowerMiddleware
          (Tower.Middleware.Tracing.withTracingGlobal testLib (Tower.Middleware.Tracing.defaultTracingConfig "test"))
      result `shouldBe` Right "hello"

testLib :: InstrumentationLibrary
testLib = InstrumentationLibrary
  { libraryName = "servant-tower-hs-test"
  , libraryVersion = "0.0.0"
  , librarySchemaUrl = ""
  , libraryAttributes = emptyAttributes
  }
