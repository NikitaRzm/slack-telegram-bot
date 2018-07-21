{-# LANGUAGE OverloadedStrings#-}
{-# LANGUAGE DeriveGeneric #-}
--{-# LANGUAGE RecordWildCards #-}

module SlackBot where

import SlackJson
import Control.Monad
import Data.Aeson
import Network.HTTP.Conduit hiding (httpLbs)
import Lib
import Data.ByteString.Char8 (pack)
import qualified Data.ByteString.Lazy as B
import Control.Monad.State
import GHC.Generics
import Control.Exception

data SlackConfig = SlackConfig {token :: String,
                                channel :: String} deriving (Show, Generic)

instance FromJSON SlackConfig
instance ToJSON SlackConfig

getMessages :: SlackConfig -> IO (Maybe [SlackMessage])
getMessages SlackConfig{token = t, channel = c} = do
  let getHistory = "https://slack.com/api/channels.history?token="
                ++ t ++ "&channel=" ++ c
  messagesStr <- catch (simpleHttp getHistory) $ return . handleHttpException
  let messagesParsed = case messagesStr of
        "" -> Left "Didn't get an answer for request, but I'm still working!"
        msg -> eitherDecode msg :: Either String SlackResponse
  return $ either (const Nothing) (Just . messages) messagesParsed

handleHttpException :: SomeException -> B.ByteString --add normal exception handling
handleHttpException e = ""