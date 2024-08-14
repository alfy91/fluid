module App.Util
   ( Attrs
   , ReactState(..)
   , SelState(..)
   , Selectable
   , Selector
   , ViewSelector
   , asℝ
   , attrs
   , class Reflect
   , colorShade
   , css
   , eventData
   , from
   , fromChangeℝ
   , fromℝ
   , get_intOrNumber
   , isInert
   , isNone
   , isPersistent
   , isPrimary
   , isSecondary
   , isTransient
   , persist
   , record
   , runAffs_
   , selClasses
   , selClassesFor
   , selState
   , selectionEventData
   , selector
   , toℝ
   , to𝔹
   , 𝕊(..)
   ) where

import Prelude hiding (absurd, join)

import Bind (Bind, Var)
import Control.Apply (lift2)
import Data.Array ((:)) as A
import Data.Array (concat)
import Data.Either (Either(..))
import Data.Foldable (foldl)
import Data.Generic.Rep (class Generic)
import Data.Int (fromStringAs, hexadecimal, toStringAs)
import Data.List (List(..), (:))
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype, over, over2)
import Data.Profunctor.Strong ((&&&), first)
import Data.Show.Generic (genericShow)
import Data.String (joinWith)
import Data.String.CodeUnits (drop, take)
import Data.Traversable (sequence, sequence_)
import Data.Tuple (snd)
import DataType (cCons, cNil)
import Dict (Dict)
import Effect (Effect)
import Effect.Aff (Aff, runAff_)
import Effect.Class.Console (log)
import Foreign.Object (Object, empty, fromFoldable, union)
import Lattice (class BoundedJoinSemilattice, class JoinSemilattice, 𝔹, bot, neg, (∨))
import Primitive (as, intOrNumber, unpack)
import Primitive as P
import Test.Util.Debug (tracing)
import Unsafe.Coerce (unsafeCoerce)
import Util (type (×), Endo, definitely', error, spyWhen)
import Util.Map (get)
import Val (class Highlightable, BaseVal(..), DictRep(..), Val(..), highlightIf)
import Web.Event.Event (Event, EventType(..), target, type_)
import Web.Event.EventTarget (EventTarget)

type Selector (f :: Type -> Type) = Endo (f (SelState 𝔹)) -- modifies selection state
type ViewSelector a = a -> Endo (Selector Val) -- convert mouse event data to view selector

-- Selection has two dimensions: persistent/transient and primary/secondary/inert. An element can be persistently
-- *and* transiently selected at the same time; these need to be visually distinct (so that for example
-- clicking during mouseover visibly changes the state). Primary and secondary also need to be visually
-- distinct but not orthogonal; primary should (visually) subsume secondary. 
-- inert is for nodes with no descendants. 
-- We implement ReactState, then TelState to possibly include none in a different location.

newtype SelState a = SelState
   { persistent :: a
   , transient :: a
   }

instance (Highlightable a, JoinSemilattice a) => Highlightable (SelState a) where
   highlightIf (SelState { persistent, transient }) = highlightIf (persistent ∨ transient)

persist :: forall a. Endo a -> Endo (SelState a)
persist δα = over SelState \s -> s { persistent = δα s.persistent }

selState :: forall a. a -> a -> SelState a
selState b1 b2 = SelState { persistent: b1, transient: b2 }

data ReactState a = Inert | Reactive (SelState a)

data 𝕊 = None | Secondary | Primary

type Selectable a = a × ReactState 𝕊

isPrimary :: ReactState 𝕊 -> 𝔹
isPrimary (Reactive (SelState { persistent, transient })) =
   persistent == Primary || transient == Primary
isPrimary Inert = false

isSecondary :: ReactState 𝕊 -> 𝔹
isSecondary (Reactive (SelState { persistent, transient })) =
   persistent == Secondary || transient == Secondary
isSecondary Inert = false

isNone :: ReactState 𝕊 -> 𝔹
isNone (Reactive (SelState { persistent, transient })) =
   persistent == None && transient == None
isNone _ = false

isInert :: ReactState 𝕊 -> 𝔹
isInert Inert = true
isInert _ = false

isPersistent :: ReactState 𝕊 -> 𝔹
isPersistent (Reactive (SelState { persistent })) = persistent /= None
isPersistent Inert = false

isTransient :: ReactState 𝕊 -> 𝔹
isTransient (Reactive (SelState { transient })) = transient /= None
isTransient Inert = false

-- UI sometimes merges 𝕊 values, e.g. x and y coordinates in a scatter plot
compare' :: 𝕊 -> 𝕊 -> Ordering
compare' None None = EQ
compare' None _ = LT
compare' Secondary Secondary = EQ
compare' Secondary Primary = LT
compare' Secondary None = GT
compare' Primary Primary = EQ
compare' Primary _ = GT

--rather than deriving instances, and just taking inert as bot whenever we derive, directly
instance Eq 𝕊 where
   eq s s' = compare' s s' == EQ

instance Ord 𝕊 where
   compare = compare'

instance JoinSemilattice 𝕊 where
   join = max

instance JoinSemilattice (ReactState 𝕊) where
   join a Inert = a
   join Inert b = b
   join (Reactive (SelState { persistent: a1, transient: b1 })) (Reactive (SelState { persistent: a2, transient: b2 })) = (Reactive (SelState { persistent: a1 ∨ a2, transient: b1 ∨ b2 }))

to𝔹 :: ReactState 𝕊 -> SelState 𝔹
--only used in tests
to𝔹 = ((_ /= None) <$> _) <<< fromℝ

--methods for initial assignation of states 
toℝ :: 𝔹 -> SelState 𝔹 -> ReactState 𝕊
toℝ true _ = Inert
toℝ false sel = Reactive (sel <#> if _ then Primary else None)

asℝ :: SelState 𝔹 -> SelState 𝔹 -> ReactState 𝕊
asℝ (SelState { persistent: a1, transient: b1 }) (SelState { persistent: a2, transient: b2 }) = (if ((a1 && not a2) || (b1 && not b2)) then Inert else Reactive (lift2 as𝕊' a b))
   where
   a = (SelState { persistent: a1, transient: b1 })
   b = (SelState { persistent: a2, transient: b2 })

   as𝕊' :: 𝔹 -> 𝔹 -> 𝕊
   as𝕊' false false = None
   as𝕊' false true = Secondary
   as𝕊' true false = Primary -- the if solves this case, (as you can't be persistent inert and transient not...)
   as𝕊' true true = Primary

-- TO FIX/REMOVE/OTHERWISE ALTER

fromℝ :: ReactState 𝕊 -> SelState 𝕊
fromℝ Inert = (SelState { persistent: None, transient: None })
fromℝ (Reactive sel) = sel

fromChangeℝ :: ReactState 𝕊 -> SelState 𝕊
fromChangeℝ Inert = (SelState { persistent: None, transient: None })
fromChangeℝ _ = (SelState { persistent: Primary, transient: Secondary })

get_intOrNumber :: Var -> Dict (Val (ReactState 𝕊)) -> Selectable Number
get_intOrNumber x r = first as (unpack intOrNumber (get x r))

-- Assumes fields are all of primitive type.
record :: forall a. (Dict (Val (ReactState 𝕊)) -> a) -> Val (ReactState 𝕊) -> a
record toRecord (Val _ v) = toRecord (P.record2.unpack v)

class Reflect a b where
   from :: Partial => a -> b

-- Discard any constructor-level annotations.
instance Reflect (Val (SelState 𝕊)) (Array (Val (SelState 𝕊))) where
   from (Val _ (Constr c Nil)) | c == cNil = []
   from (Val _ (Constr c (u1 : u2 : Nil))) | c == cCons = u1 A.: from u2

-- Discard both constructor-level annotations and key annotations.
instance Reflect (Val (SelState 𝕊)) (Dict (Val (SelState 𝕊))) where
   from (Val _ (Dictionary (DictRep d))) = d <#> snd

instance Reflect (Val (ReactState 𝕊)) (Dict (Val (ReactState 𝕊))) where
   from (Val _ (Dictionary (DictRep d))) = d <#> snd

instance Reflect (Val (ReactState 𝕊)) (Array (Val (ReactState 𝕊))) where
   from (Val _ (Constr c Nil)) | c == cNil = []
   from (Val _ (Constr c (u1 : u2 : Nil))) | c == cCons = u1 A.: from u2

runAffs_ :: forall a. (a -> Effect Unit) -> Array (Aff a) -> Effect Unit
runAffs_ f as = flip runAff_ (sequence as) case _ of
   Left err -> log $ show err
   Right as' -> as' <#> f # sequence_

-- Unpack d3.js data and event type associated with mouse event target.
selectionEventData :: forall a. Event -> a × Selector Val
selectionEventData = eventData &&& type_ >>> selector

eventData :: forall a. Event -> a
eventData = target >>> unsafeEventData
   where
   unsafeEventData :: Maybe EventTarget -> a
   unsafeEventData tgt = (unsafeCoerce $ definitely' tgt).__data__

-- maybe we make inert unselectable
selector :: EventType -> Selector Val
selector = case _ of
   EventType "mousedown" -> (over SelState (report <<< \s -> s { persistent = neg s.persistent }) <$> _)
   EventType "mouseenter" -> (over SelState (report <<< \s -> s { transient = true }) <$> _)
   EventType "mouseleave" -> (over SelState (report <<< \s -> s { transient = false }) <$> _)
   EventType _ -> error "Unsupported event type"
   where
   report = spyWhen tracing.mouseEvent "Setting SelState to " show

-- https://stackoverflow.com/questions/5560248
colorShade :: String -> Int -> String
colorShade col n =
   -- remove and reinstate leading "#"
   "#" <> shade (take 2 $ drop 1 col) <> shade (take 2 $ drop 3 col) <> shade (take 2 $ drop 5 col)
   where
   shade :: String -> String
   shade rgbComponent =
      definitely' (fromStringAs hexadecimal rgbComponent) + n
         # clamp 0 255
         # toStringAs hexadecimal

-- need to consider inert things for this
css
   :: { sel ::
           { transient ::
                { primary :: String
                , secondary :: String
                }
           , persistent ::
                { primary :: String
                , secondary :: String
                }
           }
      , inert :: String
      }
css =
   { sel:
        { transient:
             { primary: "selected-primary-transient"
             , secondary: "selected-secondary-transient"
             }
        , persistent:
             { primary: "selected-primary-persistent"
             , secondary: "selected-secondary-persistent"
             }
        }
   , inert: "inert"
   }

selClasses :: String
selClasses = joinWith " " $
   [ css.sel.transient.primary
   , css.sel.transient.secondary
   , css.sel.persistent.primary
   , css.sel.persistent.secondary
   , css.inert
   ]

selClassesFor :: ReactState 𝕊 -> String
selClassesFor Inert =
   joinWith " " $ concat
      [ [ css.inert ] ]
selClassesFor (Reactive (SelState s)) =
   joinWith " " $ concat
      [ case s.persistent of
           Secondary -> [ css.sel.persistent.secondary ]
           Primary -> [ css.sel.persistent.primary ]
           None -> []
      , case s.transient of
           Secondary -> [ css.sel.transient.secondary ]
           Primary -> [ css.sel.transient.primary ]
           None -> []
      ]

type Attrs = Array (Bind String)

attrs :: Array Attrs -> Object String
attrs = foldl (\kvs -> (kvs `union` _) <<< fromFoldable) empty

-- ======================
-- boilerplate
-- ======================

derive instance Generic 𝕊 _
instance Show 𝕊 where
   show = genericShow

derive instance Newtype (SelState a) _
derive instance Functor SelState
derive instance Functor ReactState

instance Apply SelState where
   apply (SelState fs) (SelState s) =
      SelState { persistent: fs.persistent s.persistent, transient: fs.transient s.transient }

derive instance Ord a => Ord (SelState a)
derive instance Eq a => Eq (SelState a)
derive newtype instance Show a => Show (SelState a)

instance JoinSemilattice a => JoinSemilattice (SelState a) where
   join = over2 SelState \s1 s2 ->
      { persistent: s1.persistent ∨ s2.persistent, transient: s1.transient ∨ s2.transient }

instance BoundedJoinSemilattice a => BoundedJoinSemilattice (SelState a) where
   bot = SelState { persistent: bot, transient: bot }
