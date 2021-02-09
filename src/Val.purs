module Val where

import Prelude hiding (absurd, top)
import Data.List (List)
import Data.Maybe (Maybe(..))
import Bindings (Bindings)
import DataType (Ctr)
import Expr (Elim, RecDefs)
import Lattice (class BoundedSlices, class JoinSemilattice, class Slices, 𝔹, (∨), definedJoin, maybeJoin)
import Util (Endo, type (×), type (+), (≟), absurd, error)

-- one constructor for each PureScript type that appears in an exported operator signature
data Primitive =
   ValOp (Val 𝔹 -> Val 𝔹) |
   IntOp (Int -> Val 𝔹) |
   NumberOp (Number -> Val 𝔹) |
   IntOrNumberOp (Int + Number -> Val 𝔹) |
   StringOp (String -> Val 𝔹) |
   IntOrNumberOrStringOp (Int + Number + String -> Val 𝔹)

-- Only annotate first-order data for now.
data Val a =
   Hole |
   Int a Int |
   Float a Number |
   Str a String |
   Constr a Ctr (List (Val a)) |
   Matrix a (Array (Array (Val a))) (Int × Int) |
   Closure (Env a) (RecDefs a) (Elim a) |
   Primitive Primitive

-- The annotation on a value of primitive type.
getα :: Val 𝔹 -> 𝔹
getα Hole         = false
getα (Int α _)    = α
getα (Float α _)  = α
getα (Str α _)    = α
getα _            = error absurd

-- Set the annotation on a value of primitive type, which may not be a hole.
setα :: 𝔹 -> Endo (Val 𝔹)
setα α (Int _ n)     = Int α n
setα α (Float _ n)   = Float α n
setα α (Str _ str)   = Str α str
setα _ _             = error absurd

type Env = Bindings Val

-- ======================
-- boilerplate
-- ======================
derive instance functorVal :: Functor Val

instance joinSemilatticeVal :: JoinSemilattice a => JoinSemilattice (Val a) where
   join = definedJoin

instance slicesVal :: JoinSemilattice a => Slices (Val a) where
   maybeJoin Hole v                                = pure v
   maybeJoin v Hole                                = pure v
   maybeJoin (Int α n) (Int α' n')                 = Int (α ∨ α') <$> n ≟ n'
   maybeJoin (Float α n) (Float α' n')             = Float (α ∨ α') <$> n ≟ n'
   maybeJoin (Str α str) (Str α' str')             = Str (α ∨ α') <$> str ≟ str'
   maybeJoin (Constr α c vs) (Constr α' c' us)     = Constr (α ∨ α') <$> c ≟ c' <*> maybeJoin vs us
   maybeJoin (Matrix α vs xy) (Matrix α' vs' xy')  = Matrix (α ∨ α') <$> (maybeJoin vs vs') <*> xy ≟ xy'
   maybeJoin (Closure ρ δ σ) (Closure ρ' δ' σ')    = Closure <$> maybeJoin ρ ρ' <*> maybeJoin δ δ' <*> maybeJoin σ σ'
   maybeJoin (Primitive φ) (Primitive φ')          = Primitive <$> pure φ -- should require φ == φ'
   maybeJoin _ _                                   = Nothing

instance boundedSlices :: JoinSemilattice a => BoundedSlices (Val a) where
   botOf = const Hole
