module App.View.Util.D3
   ( class IsEmpty
   , Coord
   , Selection
   , MultiSelection
   , Margin
   , SVGElementType(..)
   , attrs
   , create
   , createMany
   , datum
   , dimensions
   , each
   , forEach_create
   , forEach_on
   , forEach_setText
   , isEmpty
   , line
   , nameCol
   , on
   , remove
   , rootSelect
   , rotate
   , rotate'
   , scaleLinear
   , select
   , selectAll
   , setAttrs
   , setAttrs'
   , setStyles
   , setText
   , textHeight
   , textWidth
   , translate
   , translate'
   , xAxis
   , yAxis
   ) where

import Prelude

import App.Util (Dimensions)
import Bind (Bind, (↦))
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Generic.Rep (class Generic)
import Data.Newtype (unwrap)
import Data.Show.Generic (genericShow)
import Data.String (toLower)
import Effect (Effect)
import Foreign.Object (Object, fromFoldable)
import Util (Endo)
import Web.Event.Event (EventType)
import Web.Event.EventTarget (EventListener)

type Margin =
   { top :: Int
   , right :: Int
   , bottom :: Int
   , left :: Int
   }

type Coord a =
   { x :: a
   , y :: a
   }

textWidth :: String -> String -> Int
textWidth class_ = textDimensions class_ >>> unwrap >>> _.width

textHeight :: String -> String -> Int
textHeight class_ = textDimensions class_ >>> unwrap >>> _.height

translate :: Coord Int -> Bind String
translate { x, y } = "transform" ↦ "translate(" <> show x <> ", " <> show y <> ")"

translate' :: forall a. (a -> Coord Int) -> Bind (a -> String)
translate' f =
   "transform" ↦ \a -> let { x, y } = f a in "translate(" <> show x <> ", " <> show y <> ")"

rotate :: Int -> Bind String
rotate n = "transform" ↦ "rotate(" <> show n <> ")"

rotate' :: forall a. (a -> Int) -> Bind (a -> String)
rotate' f = "transform" ↦ \a -> "rotate(" <> show (f a) <> ")"

data SVGElementType
   = Circle
   | G
   | Path
   | Rect
   | SVG
   | Text

create :: SVGElementType -> Selection -> Array (Bind String) -> Effect Selection
create elementType parent =
   fromFoldable >>> createChild parent (show elementType)

forEach_create :: forall a. SVGElementType -> MultiSelection -> Array (Bind (a -> String)) -> Effect MultiSelection
forEach_create elementType parents =
   fromFoldable >>> forEach_createChild parents (show elementType)

createMany :: forall a. SVGElementType -> Selection -> String -> Array a -> Array (Bind (a -> String)) -> Effect MultiSelection
createMany elementType parent class_ xs =
   fromFoldable >>> createChildren parent (show elementType) class_ xs

setAttrs :: Array (Bind String) -> Selection -> Effect Selection
setAttrs as sel =
   fromFoldable as # attrs sel

setAttrs' :: forall a. (a -> Array (Bind String)) -> Selection -> Effect Selection
setAttrs' asF sel =
   (asF >>> fromFoldable) # attrs_ sel

setStyles :: Array (Bind String) -> Selection -> Effect Selection
setStyles as sel =
   fromFoldable as # styles sel

foreign import data Selection :: Type
foreign import data MultiSelection :: Type

class IsEmpty a where
   isEmpty :: a -> Effect Boolean

instance IsEmpty Selection where
   isEmpty = empty

instance IsEmpty MultiSelection where
   isEmpty = multi_isEmpty

foreign import createChild :: Selection -> String -> Object String -> Effect Selection
foreign import createChildren :: forall a. Selection -> String -> String -> Array a -> Object (a -> String) -> Effect MultiSelection
foreign import remove :: Selection -> Effect Unit
foreign import nameCol :: String -> Array String -> String
foreign import scaleLinear :: { min :: Number, max :: Number } -> { min :: Number, max :: Number } -> Endo Number
-- Currently two different protocols for x and y axis -- will subsume into something more general
foreign import xAxis :: Coord (Endo Number) -> NonEmptyArray Number -> Selection -> Effect Selection
foreign import yAxis :: Coord (Endo Number) -> Number -> Selection -> Effect Selection
foreign import empty :: Selection -> Effect Boolean
foreign import dimensions :: Selection -> Effect (Dimensions Int) -- expects singleton selection
foreign import textDimensions :: String -> String -> Dimensions Int
foreign import line :: Coord (Endo Number) -> Array (Coord Number) -> String
foreign import rootSelect :: String -> Effect Selection
foreign import select :: Selection -> String -> Effect Selection
foreign import selectAll :: Selection -> String -> Effect MultiSelection
foreign import setText :: String -> Selection -> Effect Unit
foreign import attrs :: Selection -> Object String -> Effect Selection
foreign import attrs_ :: forall a. Selection -> (a -> Object String) -> Effect Selection
foreign import styles :: Selection -> Object String -> Effect Selection
foreign import datum :: forall a. Selection -> Effect a -- currently unused
foreign import on :: Selection -> EventListener -> Effect Unit
foreign import each :: (Selection -> Effect Selection) -> MultiSelection -> Effect MultiSelection

-- Different type signatures but same underlying implementation as Selection-based analogues
foreign import forEach_attrs_ :: forall a. MultiSelection -> (a -> Object String) -> Effect MultiSelection
foreign import forEach_createChild :: forall a. MultiSelection -> String -> Object (a -> String) -> Effect MultiSelection
foreign import forEach_on :: MultiSelection -> EventType -> EventListener -> Effect Unit
foreign import forEach_setText :: forall a. (a -> String) -> MultiSelection -> Effect Unit
foreign import multi_isEmpty :: MultiSelection -> Effect Boolean

-- ======================
-- boilerplate
-- ======================

derive instance Generic SVGElementType _

instance Show SVGElementType
   where
   show = genericShow >>> toLower
