{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Network.HTTP.Tower.ClientTLSSpec (spec) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Data.Text (pack)
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Types as HTTP
import System.Directory (createDirectoryIfMissing)
import System.Process (callCommand, readProcess)
import Test.Hspec

import qualified TestContainers as TC
import TestContainers.Hspec (withContainers)

import Network.HTTP.Tower.Client (newClientWithTLS, runRequest)
import Network.HTTP.Tower.Error (ServiceError(..))

-- | Generate test certificates: CA, server cert, client cert.
generateCerts :: FilePath -> IO ()
generateCerts dir = do
  createDirectoryIfMissing True dir
  -- CA
  callCommand $ "openssl genrsa -out " <> dir <> "/ca-key.pem 2048 2>/dev/null"
  callCommand $ "openssl req -new -x509 -key " <> dir <> "/ca-key.pem"
    <> " -out " <> dir <> "/ca.pem -days 1 -subj '/CN=Test CA' 2>/dev/null"
  -- Server (signed by CA, with SAN for localhost)
  callCommand $ "openssl genrsa -out " <> dir <> "/server-key.pem 2048 2>/dev/null"
  callCommand $ "openssl req -new -key " <> dir <> "/server-key.pem"
    <> " -out " <> dir <> "/server.csr -subj '/CN=localhost' 2>/dev/null"
  writeFile (dir <> "/san.cnf") $ unlines
    [ "[v3_req]"
    , "subjectAltName = DNS:localhost,IP:127.0.0.1"
    ]
  callCommand $ "openssl x509 -req -in " <> dir <> "/server.csr"
    <> " -CA " <> dir <> "/ca.pem -CAkey " <> dir <> "/ca-key.pem"
    <> " -CAcreateserial -out " <> dir <> "/server.pem -days 1"
    <> " -extensions v3_req -extfile " <> dir <> "/san.cnf 2>/dev/null"
  -- Client (signed by CA)
  callCommand $ "openssl genrsa -out " <> dir <> "/client-key.pem 2048 2>/dev/null"
  callCommand $ "openssl req -new -key " <> dir <> "/client-key.pem"
    <> " -out " <> dir <> "/client.csr -subj '/CN=Test Client' 2>/dev/null"
  callCommand $ "openssl x509 -req -in " <> dir <> "/client.csr"
    <> " -CA " <> dir <> "/ca.pem -CAkey " <> dir <> "/ca-key.pem"
    <> " -CAcreateserial -out " <> dir <> "/client.pem -days 1 2>/dev/null"

nginxConf :: String
nginxConf = unlines
  [ "events { worker_connections 64; }"
  , "http {"
  , "  server {"
  , "    listen 443 ssl;"
  , "    ssl_certificate /certs/server.pem;"
  , "    ssl_certificate_key /certs/server-key.pem;"
  , "    ssl_client_certificate /certs/ca.pem;"
  , "    ssl_verify_client on;"
  , "    location / { return 200 'mTLS OK'; }"
  , "  }"
  , "}"
  ]

dockerAvailable :: IO Bool
dockerAvailable = do
  result <- try (readProcess "docker" ["info"] "") :: IO (Either SomeException String)
  pure $ case result of
    Right _ -> True
    Left _  -> False

spec :: Spec
spec = describe "Client TLS (Docker)" $ beforeAll dockerAvailable $ do

  it "connects with custom CA to system HTTPS" $ \isAvailable -> do
    -- No Docker needed for this one — just test that newClientWithTLS works
    client <- newClientWithTLS Nothing Nothing
    req <- HTTP.parseRequest "https://example.com"
    result <- runRequest client req
    case result of
      Right resp -> HTTP.statusCode (HTTP.responseStatus resp) `shouldBe` 200
      Left err -> expectationFailure $ "Expected success, got: " <> show err

  it "connects with mTLS client cert to nginx" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else do
        let certDir = "/tmp/http-tower-hs-test-certs"
        generateCerts certDir
        writeFile (certDir <> "/nginx.conf") nginxConf

        withContainers (setupNginx certDir) $ \port -> do
          threadDelay 2_000_000

          client <- newClientWithTLS
            (Just (certDir <> "/ca.pem"))
            (Just (certDir <> "/client.pem", certDir <> "/client-key.pem"))
          req <- HTTP.parseRequest $ "https://localhost:" <> show port <> "/"
          result <- runRequest client req
          case result of
            Right resp -> HTTP.statusCode (HTTP.responseStatus resp) `shouldBe` 200
            Left err -> expectationFailure $ "mTLS request failed: " <> show err

  it "fails without client cert when mTLS is required" $ \isAvailable -> do
    if not isAvailable
      then pendingWith "Docker not available"
      else do
        let certDir = "/tmp/http-tower-hs-test-certs"
        generateCerts certDir
        writeFile (certDir <> "/nginx.conf") nginxConf

        withContainers (setupNginx certDir) $ \port -> do
          threadDelay 2_000_000

          client <- newClientWithTLS
            (Just (certDir <> "/ca.pem"))
            Nothing  -- no client cert
          req <- HTTP.parseRequest $ "https://localhost:" <> show port <> "/"
          result <- runRequest client req
          case result of
            Left _ -> pure ()  -- TLS handshake error
            Right resp ->
              -- nginx returns 400 when client cert is missing
              HTTP.statusCode (HTTP.responseStatus resp) `shouldSatisfy` (>= 400)

setupNginx :: FilePath -> TC.TestContainer Int
setupNginx certDir = do
  container <- TC.run $ TC.containerRequest (TC.fromTag "nginx:alpine")
    TC.& TC.setExpose [443]
    TC.& TC.setVolumeMounts
        [ (pack certDir, "/certs")
        , (pack (certDir <> "/nginx.conf"), "/etc/nginx/nginx.conf")
        ]
    TC.& TC.setWaitingFor (TC.waitUntilTimeout 30 (TC.waitUntilMappedPortReachable 443))
  pure (TC.containerPort container 443)
