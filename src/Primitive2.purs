module Primitive2 where

import Prelude
import Data.Int (toNumber)
import Data.Either (Either(..))
import Lattice (𝔹, (∧))
import Util (type (+), type (×), (×), absurd, error)

type Op a = a × 𝔹 -> Val 𝔹

data Primitive =
   IntOp (Op Int)

data Val a =
   Int a Int |
   Primitive Primitive

class To a where
   to :: Val 𝔹 -> a × 𝔹

class From a where
   from :: a × 𝔹 -> Val 𝔹

getα :: Val 𝔹 -> 𝔹
getα (Int α _) = α
getα _         = error absurd

instance toInt :: To Int where
   to (Int α n)   = n × α
   to _           = error "Int expected"

instance fromInt :: From Int where
   from (n × α) = Int α n

from1 :: (Int × 𝔹 -> Int × 𝔹) -> Val 𝔹
from1 op = Primitive (IntOp (op >>> from))

from2 :: (Int × 𝔹 -> Int × 𝔹 -> Int × 𝔹) -> Val 𝔹
from2 op = Primitive (IntOp (op >>> from1))

apply :: Primitive -> Val 𝔹 -> Val 𝔹
apply (IntOp op) v = op (to v)

plus_ :: Val 𝔹
plus_ = from2 plus

plus :: Int × 𝔹 -> Int × 𝔹 -> Int × 𝔹
plus = dependsBoth (+)

dependsBoth :: forall a b c . (a -> b -> c) -> a × 𝔹 -> b × 𝔹 -> c × 𝔹
dependsBoth op (x × α) (y × β) = x `op` y × (α ∧ β)
