{-# LANGUAGE OverloadedStrings #-}

-- | Example: Arrow composition with HTTP services.
--
-- Demonstrates building a multi-step API pipeline using:
--
--   * @(&)@ for applying built-in resilience middleware (retry, timeout, etc.)
--   * @(>>>)@ for chaining services with different input\/output types
--   * @arr@ for pure transformations between steps
--   * @second@ for carrying data through the pipeline
--   * @(|||)@ for routing to different handlers based on a condition
--
-- Fetches a post from JSONPlaceholder, then fetches the post's author,
-- and combines both into a summary. All with automatic error short-circuiting —
-- if any step fails, the pipeline stops and returns the error.
--
-- Run with: @stack run example-arrow-pipeline@
module Main where

import Control.Arrow (arr, second, (|||))
import Control.Category ((>>>))
import Data.Aeson (eitherDecode, (.:), FromJSON(..), withObject)
import Data.Function ((&))
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Network.HTTP.Client as HTTP

import Tower hiding (withLogging)
import Network.HTTP.Tower

-------------------------------------------------------------------------------
-- Domain types
-------------------------------------------------------------------------------

-- | A blog post from the JSONPlaceholder API.
data Post = Post
  { postUserId :: Int
  , postTitle  :: T.Text
  } deriving Show

instance FromJSON Post where
  parseJSON = withObject "Post" $ \v -> Post
    <$> v .: "userId"
    <*> v .: "title"

-- | A user from the JSONPlaceholder API.
data User = User
  { userName  :: T.Text
  , userEmail :: T.Text
  } deriving Show

instance FromJSON User where
  parseJSON = withObject "User" $ \v -> User
    <$> v .: "name"
    <*> v .: "email"

-- | Combined result: a post with its author's info.
data PostWithAuthor = PostWithAuthor
  { pwaTitle       :: T.Text
  , pwaAuthorName  :: T.Text
  , pwaAuthorEmail :: T.Text
  } deriving Show

-------------------------------------------------------------------------------
-- Reusable service: JSON response parser
-------------------------------------------------------------------------------

-- | Parse a JSON response body into a domain type.
-- Fails with 'CustomError' if the JSON doesn't decode.
parseJson :: FromJSON a => Service (HTTP.Response LBS.ByteString) a
parseJson = Service $ \resp ->
  pure $ case eitherDecode (HTTP.responseBody resp) of
    Left err -> Left (CustomError (T.pack err))
    Right a  -> Right a

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "=== Arrow pipeline example ===\n"

  -- Create HTTP client with resilience middleware applied via (&)
  client  <- newClient
  breaker <- newCircuitBreaker
  let cbConfig = CircuitBreakerConfig
        { cbFailureThreshold = 5
        , cbCooldownPeriod   = 30
        }
      http :: Service HTTP.Request (HTTP.Response LBS.ByteString)
      http = clientService $ client & applyMiddleware
        ( withRetry (constantBackoff 2 1.0)
        . withTimeout 5000
        . withCircuitBreaker cbConfig breaker
        . withUserAgent "tower-hs-arrow-example/0.1"
        . withValidateStatus (\c -> c >= 200 && c < 300)
        . withLogging T.putStrLn
        )

  ---------------------------------------------------------------------------
  -- Build domain services with arrow composition
  ---------------------------------------------------------------------------

  -- Fetch a post by ID: Int → Post
  let fetchPost :: Service Int Post
      fetchPost =
            arr (\pid -> HTTP.parseRequest_
                   $ "https://jsonplaceholder.typicode.com/posts/" <> show pid)
        >>> http
        >>> parseJson

  -- Fetch a user by ID: Int → User
  let fetchUser :: Service Int User
      fetchUser =
            arr (\uid -> HTTP.parseRequest_
                   $ "https://jsonplaceholder.typicode.com/users/" <> show uid)
        >>> http
        >>> parseJson

  ---------------------------------------------------------------------------
  -- Pipeline 1: sequential composition with >>>
  --
  -- Fetch a post, then fetch its author, combine into a summary.
  -- Uses `second` to carry the post title alongside the user fetch.
  ---------------------------------------------------------------------------

  let fetchPostWithAuthor :: Service Int PostWithAuthor
      fetchPostWithAuthor =
            fetchPost
        >>> arr (\post -> (postTitle post, postUserId post))
        >>> second fetchUser
        >>> arr (\(title, user) -> PostWithAuthor title (userName user) (userEmail user))

  putStrLn "--- Pipeline 1: fetch post #1 then fetch its author ---"
  result1 <- runService fetchPostWithAuthor 1
  case result1 of
    Left err -> T.putStrLn $ "Failed: " <> displayError err
    Right pwa -> do
      putStrLn $ "  Post:   " <> T.unpack (pwaTitle pwa)
      putStrLn $ "  Author: " <> T.unpack (pwaAuthorName pwa)
                              <> " <" <> T.unpack (pwaAuthorEmail pwa) <> ">"

  ---------------------------------------------------------------------------
  -- Pipeline 2: ArrowChoice routing with |||
  --
  -- Fetch a post, then route based on the author's user ID:
  --   - userId <= 5  → fetch the full author profile (another HTTP call)
  --   - userId > 5   → skip the fetch, use a placeholder
  -- This shows how middleware stacks and arrow routing compose.
  ---------------------------------------------------------------------------

  let routedPipeline :: Service Int PostWithAuthor
      routedPipeline =
            fetchPost
        >>> arr (\post ->
              if postUserId post <= 5
                then Left  (postTitle post, postUserId post)   -- will fetch author
                else Right (postTitle post))                   -- skip fetch
        >>> (   (second fetchUser >>> arr (\(t, u) -> PostWithAuthor t (userName u) (userEmail u)))
            ||| arr (\t -> PostWithAuthor t "(skipped)" "")
            )

  putStrLn "\n--- Pipeline 2: fetch post #3 with ArrowChoice routing ---"
  result2 <- runService routedPipeline 3
  case result2 of
    Left err -> T.putStrLn $ "Failed: " <> displayError err
    Right pwa -> do
      putStrLn $ "  Post:   " <> T.unpack (pwaTitle pwa)
      putStrLn $ "  Author: " <> T.unpack (pwaAuthorName pwa)

  putStrLn "\n--- Pipeline 2: fetch post #51 (userId=6 > 5, skips author fetch) ---"
  result3 <- runService routedPipeline 51
  case result3 of
    Left err -> T.putStrLn $ "Failed: " <> displayError err
    Right pwa -> do
      putStrLn $ "  Post:   " <> T.unpack (pwaTitle pwa)
      putStrLn $ "  Author: " <> T.unpack (pwaAuthorName pwa)

  ---------------------------------------------------------------------------
  -- Error short-circuiting demo
  ---------------------------------------------------------------------------

  putStrLn "\n--- Error demo: fetch non-existent post #9999 ---"
  result4 <- runService fetchPostWithAuthor 9999
  case result4 of
    Left err -> T.putStrLn $ "  Short-circuited: " <> displayError err
    Right _  -> putStrLn "  Unexpected success"
