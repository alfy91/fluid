module Lattice where

import Prelude hiding (absurd, join, top)
import Control.Apply (lift2)
import Data.Array (length, zipWith) as A
import Data.List (List, length, zipWith)
import Data.Map (Map, fromFoldable, toUnfoldable)
import Data.Map.Internal (keys)
import Data.Maybe (Maybe(..))
import Data.Profunctor.Strong (second)
import Data.Traversable (sequence)
import Data.Tuple (Tuple)
import Util ((×), (≟), absurd, error, fromJust)

class JoinSemilattice a where
   join :: a -> a -> a

class JoinSemilattice a <= BoundedJoinSemilattice a where
   bot :: a

instance joinSemilatticeBoolean :: JoinSemilattice Boolean where
   join = (||)

instance boundedJoinSemilatticeBoolean :: BoundedJoinSemilattice Boolean where
   bot = false

instance joinSemilatticeUnit :: JoinSemilattice Unit where
   join _ = identity

instance boundedJoinSemilatticeUnit :: BoundedJoinSemilattice Unit where
   bot = unit

-- Sometimes convenient to assume join defined even if it may not be.
class JoinSemilattice a <= Slices a where
   maybeJoin :: a -> a -> Maybe a

definedJoin :: forall a . Slices a => a -> a -> a
definedJoin x = fromJust "Join undefined" <<< maybeJoin x

class Slices a <= BoundedSlices a where
   botOf :: a -> a

-- Give ∧ and ∨ same associativity and precedence as * and +
infixl 7 meet as ∧
infixl 6 join as ∨

type 𝔹 = Boolean

-- don't need a meet semilattice typeclass just yet
meet :: Boolean -> Boolean -> Boolean
meet = (&&)

instance joinSemilatticeTuple :: (Eq k, Slices t) => JoinSemilattice (Tuple k t) where
   join = definedJoin

instance slicesTuple :: (Eq k, Slices t) => Slices (Tuple k t) where
   maybeJoin (k × v) (k' × v') = (k ≟ k') `lift2 (×)` maybeJoin v v'

instance joinSemilatticeList :: Slices t => JoinSemilattice (List t) where
   join = definedJoin

instance slicesList :: Slices t => Slices (List t) where
   maybeJoin xs ys
      | length xs == length ys   = sequence $ zipWith maybeJoin xs ys
      | otherwise                = Nothing

instance boundedSlicesList :: BoundedSlices t => BoundedSlices (List t) where
   botOf = map botOf

instance joinSemilatticeMap :: (Ord k, Slices t) => JoinSemilattice (Map k t) where
   join = definedJoin

instance slicesMap :: (Ord k, Slices t) => Slices (Map k t) where
   maybeJoin m m'
      | keys m == keys m'  = fromFoldable <$> (sequence $ zipWith maybeJoin (toUnfoldable m) (toUnfoldable m'))
      | otherwise          = Nothing

instance joinSemilatticeArrayArray :: Slices a => JoinSemilattice (Array a) where
   join = definedJoin

instance slicesArrayArray :: Slices a => Slices (Array a) where
   maybeJoin xs ys
      | A.length xs == A.length ys  = sequence $ A.zipWith maybeJoin xs ys
      | otherwise                   = Nothing

class Expandable a where
   -- Partial function defined iff x is above x', which expands in x any subtree prefixes which are expanded in x'
   expand :: a -> a -> a

instance expandableMap :: (Ord k, Expandable (t a)) => Expandable (Map k (t a)) where
   expand m m'
      | keys m == keys m'  = fromFoldable (zipWith expandValue (toUnfoldable m) (toUnfoldable m'))
      where
      expandValue (k × x) (_ × x') = k × expand x x'
      | otherwise          = error absurd
