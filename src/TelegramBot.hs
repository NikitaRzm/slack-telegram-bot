{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module TelegramBot where

import TelegramConfig
import TelegramJson
import EchoBot
import Control.Monad.State
import Control.Monad (void)
import Data.Aeson
import Network.HTTP.Conduit hiding (httpLbs)
import Lib
import Data.ByteString.Char8 (pack)
import qualified Data.ByteString.Lazy as B
import Control.Exception


data TelegramBot = TelegramBot { config :: TelegramConfig
                               , botUrl :: String
                               , getUpdates :: String
                               , sendMessage :: String
                               , lastMessId :: Integer
                               , waitingForRepeats :: Bool }

instance EchoBot TelegramBot TelegramMessage TelegramConfig where
  getBotWithConfig c =
    let bUrl = "https://api.telegram.org/bot" ++ token c ++ "/"
        in TelegramBot c bUrl (bUrl ++ "getUpdates") 
          (bUrl ++ "sendMessage") 0 False

  getLastMessage = do
    tBot@TelegramBot{config = c, getUpdates = updStr, lastMessId = oldId} <- get
    updatesStr <- liftIO $ catch (simpleHttp updStr) $ return . handleHttpException
    let updates = case updatesStr of
          "" -> Left "Didn't get an answer for request, but I'm still working!"
          upd -> eitherDecode upd :: Either String Updates
        m = processUpdates c oldId updates
    put $ maybe tBot (\msg -> tBot{lastMessId = message_id msg}) m
    return m

  processMessage b@TelegramBot{config = c, sendMessage = sendUrl, waitingForRepeats = wr} m = do
    let txt = text m
        chatId = chat_id $ chat m
        mId = message_id m
        sendTxt mText = sendText mText chatId sendUrl
        returnBot wFr = return $ b{lastMessId = mId, waitingForRepeats = wFr}
    case txt of
      "/help" -> sendTxt (help c ++ "\"}") >> returnBot False
      "/repeat" -> sendTxt ("select repeats count:" ++ keyboard) >> returnBot True
      t         -> if not wr || t `notElem` keyboardAnswers
                      then replicateM_ (repeats c) (sendTxt $ t ++ "\"}") >> returnBot False
                      else return $ changeRepeats b mId $ read txt

changeRepeats :: TelegramBot -> Integer -> Int -> TelegramBot
changeRepeats b@TelegramBot{config = c} newId r =
  b{lastMessId = newId, config = c{repeats = r}, waitingForRepeats = False}

sendText :: String -> Integer -> String -> IO ()
sendText txt chatId sendUrl = send sendUrl
 (RequestBodyBS $ pack $ "{\"chat_id\": "++ show chatId ++
  ",\"text\": \"" ++ txt)

keyboard :: String
keyboard = "\",\"reply_markup\": {\"keyboard\":[[\"1\",\"2\",\"3\",\"4\",\"5\"]],\"resize_keyboard\": true, \"one_time_keyboard\": true}}"

keyboardAnswers :: [String]
keyboardAnswers = ["1", "2", "3", "4", "5"]

processUpdates :: TelegramConfig -> Integer -> Either String Updates -> Maybe TelegramMessage
processUpdates c lastId = either (const Nothing) (findLastMessage lastId . result)

findLastMessage :: Integer -> [Update] -> Maybe TelegramMessage
findLastMessage oldId [] = Nothing
findLastMessage oldId (x:xs) = let mess = message x
                                   messId = message_id mess
                                   in if messId > oldId
                                         then Just mess
                                         else findLastMessage oldId xs

handleHttpException :: SomeException -> B.ByteString
handleHttpException e = ""