module Network.HTTP.Tower.Middleware.TestDouble
  ( withMock
  , withMockMap
  , withRecorder
  ) where

import Data.ByteString (ByteString)
import Data.IORef
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Network.HTTP.Client as HTTP

import Network.HTTP.Tower.Client (HttpResponse)
import Network.HTTP.Tower.Core (Service(..), Middleware)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Replace the inner service entirely with a mock function.
-- The inner service is never called.
--
-- @
-- let mock = withMock (\\req -> pure (Right fakeResponse))
-- let client' = client |> mock
-- @
withMock
  :: (HTTP.Request -> IO (Either ServiceError HttpResponse))
  -> Middleware HTTP.Request HttpResponse
withMock handler _inner = Service handler

-- | Route requests to different mock responses based on host+path.
-- Falls through to the inner service if no match is found.
--
-- @
-- let mocks = Map.fromList
--       [ ("api.example.com/v1/users", Right usersResponse)
--       , ("api.example.com/v1/health", Right healthResponse)
--       ]
-- let client' = client |> withMockMap mocks
-- @
withMockMap
  :: Map ByteString (Either ServiceError HttpResponse)
  -> Middleware HTTP.Request HttpResponse
withMockMap routes inner = Service $ \req ->
  let key = HTTP.host req <> HTTP.path req
  in case Map.lookup key routes of
    Just result -> pure result
    Nothing     -> runService inner req

-- | Record all requests that pass through, then forward to the inner service.
-- Returns the recorder IORef that can be inspected after the test.
--
-- @
-- recorder <- newIORef []
-- let client' = client |> withRecorder recorder
-- _ <- runRequest client' someRequest
-- recorded <- readIORef recorder
-- length recorded \`shouldBe\` 1
-- @
withRecorder :: IORef [HTTP.Request] -> Middleware HTTP.Request HttpResponse
withRecorder ref inner = Service $ \req -> do
  modifyIORef' ref (req :)
  runService inner req
