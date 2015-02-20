{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Servant.API.ContentTypesSpec where

import           Control.Applicative
import           Data.Aeson
import           Data.Function            (on)
import           Data.Proxy

import           Data.ByteString.Char8
import qualified Data.ByteString.Lazy     as BSL
import           Data.List                (maximumBy)
import           Data.Maybe               (fromJust, isJust)
import           Data.String              (IsString (..))
import           Data.String.Conversions  (cs)
import qualified Data.Text                as TextS
import qualified Data.Text.Lazy           as TextL
import           GHC.Generics
import           Test.Hspec
import           Test.QuickCheck

import           Servant.API.ContentTypes

spec :: Spec
spec = describe "Servant.API.ContentTypes" $ do

    describe "The JSON Content-Type type" $ do

        it "has fromByteString reverse toByteString for valid top-level json ([Int]) " $ do
            let p = Proxy :: Proxy JSON
            property $ \x -> fromByteString p (toByteString p x) == Right (x::[Int])

        it "has fromByteString reverse toByteString for valid top-level json " $ do
            let p = Proxy :: Proxy JSON
            property $ \x -> fromByteString p (toByteString p x) == Right (x::SomeData)

    describe "The PlainText Content-Type type" $ do

        it "has fromByteString reverse toByteString (lazy Text)" $ do
            let p = Proxy :: Proxy PlainText
            property $ \x -> fromByteString p (toByteString p x) == Right (x::TextL.Text)

        it "has fromByteString reverse toByteString (strict Text)" $ do
            let p = Proxy :: Proxy PlainText
            property $ \x -> fromByteString p (toByteString p x) == Right (x::TextS.Text)

    describe "The OctetStream Content-Type type" $ do

        it "is id (Lazy ByteString)" $ do
            let p = Proxy :: Proxy OctetStream
            property $ \x -> toByteString p x == (x :: BSL.ByteString)
                && fromByteString p x == Right x

        it "is fromStrict/toStrict (Strict ByteString)" $ do
            let p = Proxy :: Proxy OctetStream
            property $ \x -> toByteString p x == BSL.fromStrict (x :: ByteString)
                && fromByteString p (BSL.fromStrict x) == Right x

    describe "handleAcceptH" $ do

        it "returns Just if the 'Accept' header matches" $ do
            handleAcceptH (Proxy :: Proxy '[JSON]) "*/*" (3 :: Int)
                `shouldSatisfy` isJust
            handleAcceptH (Proxy :: Proxy '[PlainText, JSON]) "application/json" (3 :: Int)
                `shouldSatisfy` isJust
            handleAcceptH (Proxy :: Proxy '[PlainText, JSON, OctetStream])
                "application/octet-stream" ("content" :: ByteString)
                `shouldSatisfy` isJust

        it "returns the Content-Type as the first element of the tuple" $ do
            handleAcceptH (Proxy :: Proxy '[JSON]) "*/*" (3 :: Int)
                `shouldSatisfy` ((== "application/json;charset=utf-8") . fst . fromJust)
            handleAcceptH (Proxy :: Proxy '[PlainText, JSON]) "application/json" (3 :: Int)
                `shouldSatisfy` ((== "application/json;charset=utf-8") . fst . fromJust)
            handleAcceptH (Proxy :: Proxy '[PlainText, JSON, OctetStream])
                "application/octet-stream" ("content" :: ByteString)
                `shouldSatisfy` ((== "application/octet-stream") . fst . fromJust)

        it "returns the appropriately serialized representation" $ do
            property $ \x -> handleAcceptH (Proxy :: Proxy '[JSON]) "*/*" (x :: SomeData)
                == Just ("application/json;charset=utf-8", encode x)

        it "respects the Accept spec ordering" $
            property $ \a b c i -> fst (fromJust $ val a b c i) == (fst $ highest a b c)
              where
                highest a b c = maximumBy (compare `on` snd)
                    [ ("application/octet-stream", a)
                    , ("application/json;charset=utf-8", b)
                    , ("text/plain;charset=utf-8", c)
                    ]
                acceptH a b c = addToAccept (Proxy :: Proxy OctetStream) a $
                                addToAccept (Proxy :: Proxy JSON) b $
                                addToAccept (Proxy :: Proxy PlainText ) c ""
                val a b c i = handleAcceptH (Proxy :: Proxy '[OctetStream, JSON, PlainText])
                                            (acceptH a b c) (i :: Int)

data SomeData = SomeData { record1 :: String, record2 :: Int }
    deriving (Generic, Eq, Show)

newtype ZeroToOne = ZeroToOne Float
    deriving (Eq, Show, Ord)

instance FromJSON SomeData

instance ToJSON SomeData

instance Arbitrary SomeData where
    arbitrary = SomeData <$> arbitrary <*> arbitrary

instance Arbitrary TextL.Text where
    arbitrary = TextL.pack <$> arbitrary

instance Arbitrary TextS.Text where
    arbitrary = TextS.pack <$> arbitrary

instance Arbitrary ZeroToOne where
    arbitrary = ZeroToOne <$> elements [ x / 10 | x <- [1..10]]

instance MimeRender OctetStream Int where
    toByteString _ = cs . show

instance MimeRender PlainText Int where
    toByteString _ = cs . show

instance MimeRender PlainText ByteString where
    toByteString _ = cs

instance ToJSON ByteString where
    toJSON x = object [ "val" .= x ]

instance IsString AcceptHeader where
    fromString = AcceptHeader . fromString

instance Arbitrary BSL.ByteString where
    arbitrary = cs <$> (arbitrary :: Gen String)

instance Arbitrary ByteString where
    arbitrary = cs <$> (arbitrary :: Gen String)

addToAccept :: Accept a => Proxy a -> ZeroToOne -> AcceptHeader -> AcceptHeader
addToAccept p (ZeroToOne f) (AcceptHeader h) = AcceptHeader (cont h)
    where new = cs (show $ contentType p) `append` "; q=" `append` pack (show f)
          cont "" = new
          cont old = old `append` ", " `append` new
