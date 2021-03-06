{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module TelegramBot where

import Control.Exception
import Control.Monad (void)
import Control.Monad.State
import Data.Aeson
import Data.ByteString.Char8 (pack)
import qualified Data.ByteString.Lazy as B
import EchoBot
import Network.HTTP.Conduit hiding (httpLbs)
import Requests (sendTelegram)
import TelegramConfig
import TelegramJson

data TelegramBot = TelegramBot
  { config :: TelegramConfig
  , botUrl :: String
  , getUpdates :: String
  , sendMessage :: String
  , lastMessId :: Integer
  , waitingForRepeats :: Bool
  }

instance EchoBot TelegramBot TelegramMessage TelegramConfig where
  getBotWithConfig c =
    let bUrl = "https://api.telegram.org/bot" ++ token c ++ "/"
     in TelegramBot
          c
          bUrl
          (bUrl ++ "getUpdates")
          (bUrl ++ "sendMessage")
          0
          False
  getLastMessage tBot@TelegramBot { config = c
                                  , getUpdates = updStr
                                  , lastMessId = oldId
                                  } = do
    updatesStr <-
      try $ simpleHttp updStr :: IO (Either SomeException B.ByteString)
    case updatesStr of
      (Left e) -> do
        writeFile "telegram.log" $
          "Caught exception while getting last message: " ++ show e
        return Nothing
      (Right upd) -> do
        let updates = eitherDecode upd :: Either String Updates
        return $ processUpdates oldId updates
  processMessage b@TelegramBot { config = c
                               , sendMessage = sendUrl
                               , waitingForRepeats = wr
                               } m = do
    let txt = text m
        chatId = chat_id $ chat m
        mId = message_id m
        sendTxt mText = sendText mText chatId sendUrl
        returnBot wFr = return $ b {lastMessId = mId, waitingForRepeats = wFr}
    case txt of
      "/help" -> sendTxt (help c ++ "\"}") >> returnBot False
      "/repeat" ->
        sendTxt ("select repeats count:" ++ keyboard) >> returnBot True
      t ->
        if not wr || t `notElem` keyboardAnswers
          then replicateM_ (repeats c) (sendTxt $ t ++ "\"}") >> returnBot False
          else changeRepeats (read txt) <$> returnBot False

changeRepeats :: Int -> TelegramBot -> TelegramBot
changeRepeats r b@TelegramBot {config = c} = b {config = c {repeats = r}}

sendText :: String -> Integer -> String -> IO ()
sendText txt chatId sendUrl =
  catch
    (sendTelegram
       sendUrl
       (RequestBodyBS $
        pack $ "{\"chat_id\": " ++ show chatId ++ ",\"text\": \"" ++ txt))
    handleException

keyboard :: String
keyboard =
  "\",\"reply_markup\": {\"keyboard\":[[\"1\",\"2\",\"3\",\"4\",\"5\"]],\"resize_keyboard\": true, \"one_time_keyboard\": true}}"

keyboardAnswers :: [String]
keyboardAnswers = ["1", "2", "3", "4", "5"]

processUpdates :: Integer -> Either String Updates -> Maybe TelegramMessage
processUpdates lastId = either (const Nothing) (findLastMessage lastId . result)

findLastMessage :: Integer -> [Update] -> Maybe TelegramMessage
findLastMessage oldId [] = Nothing
findLastMessage oldId (x:xs) =
  let mess = message x
      messId = message_id mess
   in if messId > oldId
        then Just mess
        else findLastMessage oldId xs

handleException :: SomeException -> IO ()
handleException e =
  writeFile "telegram.log" $
  "Caught exception while sending message: " ++ show e
