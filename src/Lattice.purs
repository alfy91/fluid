module Lattice where

import Prelude hiding (absurd, join, top)
import Control.Apply (lift2)
import Data.Array (zipWith) as A
import Data.Foldable (length, foldM)
import Data.List (List, zipWith)
import Data.List.NonEmpty (NonEmptyList)
import Data.List.NonEmpty (zipWith) as NEL
import Data.Maybe (Maybe(..))
import Data.Profunctor.Strong (second)
import Data.Set (subset)
import Data.Traversable (sequence)
import Data.Tuple (Tuple)
import Dict (Dict, difference, intersectionWith, lookup, insert, keys, toUnfoldable, union, update)
import Bindings (Var)
import Util (Endo, MayFail, type (×), (×), (≞), assert, report, successfulWith)

class JoinSemilattice a where
   join :: a -> a -> a
   neg :: Endo a

class JoinSemilattice a <= BoundedJoinSemilattice a where
   bot :: a

instance JoinSemilattice Boolean where
   join = (||)
   neg = not

instance BoundedJoinSemilattice Boolean where
   bot = false

instance JoinSemilattice Unit where
   join _ = identity
   neg = identity

instance BoundedJoinSemilattice Unit where
   bot = unit

-- Need "soft failure" for joining incompatible eliminators so we can use it to desugar function clauses.
class JoinSemilattice a <= Slices a where
   maybeJoin :: a -> a -> MayFail a

definedJoin :: forall a . Slices a => a -> a -> a
definedJoin x = successfulWith "Join undefined" <<< maybeJoin x

botOf :: forall t a . Functor t => BoundedJoinSemilattice a => Endo (t a)
botOf = (<$>) (const bot)

topOf :: forall t a . Functor t => BoundedJoinSemilattice a => Endo (t a)
topOf = (<$>) (const bot >>> neg)

-- Give ∧ and ∨ same associativity and precedence as * and +
infixl 7 meet as ∧
infixl 6 join as ∨

type 𝔹 = Boolean

-- don't need a meet semilattice typeclass just yet
meet :: Boolean -> Boolean -> Boolean
meet = (&&)

instance (Eq k, Show k, Slices t) => JoinSemilattice (Tuple k t) where
   join = definedJoin
   neg = second neg

instance (Eq k, Show k, Slices t) => Slices (Tuple k t) where
   maybeJoin (k × v) (k' × v') = (k ≞ k') `lift2 (×)` maybeJoin v v'

instance Slices t => JoinSemilattice (List t) where
   join = definedJoin
   neg = (<$>) neg

instance Slices t => JoinSemilattice (NonEmptyList t) where
   join = definedJoin
   neg = (<$>) neg

instance Slices t => Slices (List t) where
   maybeJoin xs ys
      | (length xs :: Int) == length ys   = sequence (zipWith maybeJoin xs ys)
      | otherwise                         = report "Mismatched lengths"

instance Slices t => Slices (NonEmptyList t) where
   maybeJoin xs ys
      | (length xs :: Int) == length ys   = sequence (NEL.zipWith maybeJoin xs ys)
      | otherwise                         = report "Mismatched lengths"

instance Slices t => JoinSemilattice (Dict t) where
   join = definedJoin
   neg = (<$>) neg

instance Slices t => Slices (Dict t) where
   maybeJoin m m' = foldM mayFailUpdate m (toUnfoldable m' :: List (Var × t))

mayFailUpdate :: forall t . Slices t => Dict t -> Var × t -> MayFail (Dict t)
mayFailUpdate m (k × v) =
   case lookup k m of
      Nothing -> pure (insert k v m)
      Just v' -> update <$> (const <$> Just <$> maybeJoin v' v) <@> k <@> m

instance Slices a => JoinSemilattice (Array a) where
   join = definedJoin
   neg = (<$>) neg

instance Slices a => Slices (Array a) where
   maybeJoin xs ys
      | length xs == (length ys :: Int)   = sequence (A.zipWith maybeJoin xs ys)
      | otherwise                         = report "Mismatched lengths"

class Expandable a where
   expand :: a -> a -> a

instance (Functor t, BoundedJoinSemilattice a, Expandable (t a)) => Expandable (Dict (t a)) where
   expand kvs kvs' =
      assert (keys kvs `subset` keys kvs') $
      (kvs `intersectionWith expand` kvs') `union` ((kvs' `difference` kvs) <#> botOf)

instance Expandable a => Expandable (List a) where
   expand xs ys = zipWith expand xs ys

instance Expandable a => Expandable (Array a) where
   expand xs ys = A.zipWith expand xs ys
