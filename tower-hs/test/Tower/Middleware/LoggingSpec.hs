{-# LANGUAGE OverloadedStrings #-}

module Tower.Middleware.LoggingSpec (spec) where

import Data.IORef
import qualified Data.Text
import Data.Text (Text, isInfixOf)
import Test.Hspec

import Tower.Service
import Tower.Error
import Tower.Error.Testing ()
import Tower.Middleware.Logging

spec :: Spec
spec = describe "Logging middleware (generic)" $ do
  it "logs successful requests" $ do
    logRef <- newIORef ([] :: [Text])
    let logger msg = modifyIORef' logRef (msg :)
        formatter _ result duration = case result of
          Right res -> "OK: " <> res <> " (" <> showMs duration <> ")"
          Left err  -> "ERR: " <> displayError err
        svc :: Service () Text
        svc = Service $ \_ -> pure (Right "done")
        logged = withLogging formatter logger svc
    _ <- runService logged ()
    logs <- readIORef logRef
    length logs `shouldBe` 1
    isInfixOf "OK: done" (head logs) `shouldBe` True

  it "logs failed requests" $ do
    logRef <- newIORef ([] :: [Text])
    let logger msg = modifyIORef' logRef (msg :)
        formatter _ result _ = case result of
          Right _  -> "OK"
          Left err -> "ERR: " <> displayError err
        svc :: Service () Text
        svc = Service $ \_ -> pure (Left TimeoutError)
        logged = withLogging formatter logger svc
    _ <- runService logged ()
    logs <- readIORef logRef
    length logs `shouldBe` 1
    isInfixOf "ERR" (head logs) `shouldBe` True

  it "does not alter the result" $ do
    let logger _ = pure ()
        formatter _ _ _ = "ignored"
        svc :: Service () Text
        svc = Service $ \_ -> pure (Right "original")
        logged = withLogging formatter logger svc
    result <- runService logged ()
    result `shouldBe` Right "original"

  it "passes the request to the formatter" $ do
    logRef <- newIORef ([] :: [Text])
    let logger msg = modifyIORef' logRef (msg :)
        formatter req _ _ = "request=" <> req
        svc :: Service Text Text
        svc = Service $ \_ -> pure (Right "ok")
        logged = withLogging formatter logger svc
    _ <- runService logged "my-request"
    logs <- readIORef logRef
    head logs `shouldBe` "request=my-request"

showMs :: Double -> Text
showMs d = let ms = round (d * 1000) :: Int
           in Data.Text.pack (show ms) <> "ms"
