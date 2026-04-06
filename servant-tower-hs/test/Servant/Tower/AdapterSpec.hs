{-# LANGUAGE OverloadedStrings #-}

module Servant.Tower.AdapterSpec (spec) where

import Control.Exception (toException)
import Test.Hspec

import Servant.Client (ClientError(..))
import Tower.Error (ServiceError(..))
import Tower.Error.Testing ()
import Servant.Tower.Adapter (toClientError, toServiceError)

spec :: Spec
spec = describe "Servant.Tower.Adapter" $ do
  describe "toServiceError" $ do
    it "maps ConnectionError to TransportError" $ do
      let clientErr = ConnectionError (toException (userError "connection refused"))
          svcErr = toServiceError clientErr
      case svcErr of
        TransportError _ -> pure ()
        other -> expectationFailure $ "Expected TransportError, got: " ++ show other

  describe "toClientError" $ do
    it "maps TimeoutError to ConnectionError" $ do
      let svcErr = TimeoutError
          clientErr = toClientError svcErr
      case clientErr of
        ConnectionError _ -> pure ()
        other -> expectationFailure $ "Expected ConnectionError, got: " ++ show other

    it "maps CircuitBreakerOpen to ConnectionError" $ do
      let svcErr = CircuitBreakerOpen
          clientErr = toClientError svcErr
      case clientErr of
        ConnectionError _ -> pure ()
        other -> expectationFailure $ "Expected ConnectionError, got: " ++ show other

    it "maps CustomError to ConnectionError" $ do
      let svcErr = CustomError "test error"
          clientErr = toClientError svcErr
      case clientErr of
        ConnectionError _ -> pure ()
        other -> expectationFailure $ "Expected ConnectionError, got: " ++ show other

    it "unwraps RetryExhausted" $ do
      let svcErr = RetryExhausted 3 TimeoutError
          clientErr = toClientError svcErr
      case clientErr of
        ConnectionError _ -> pure ()
        other -> expectationFailure $ "Expected ConnectionError, got: " ++ show other
