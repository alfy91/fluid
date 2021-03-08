module Primitive2 where

import Prelude hiding (absurd, apply)
import Data.Either (Either(..))
import Data.Foldable (foldl)
import Data.Int (ceil, floor, toNumber)
import Data.List (List(..), (:))
import Debug.Trace (trace)
import Math (log, pow)
import Bindings (Bindings(..), (:+:), (↦))
import DataType (Ctr, cCons, cFalse, cPair, cTrue)
import Lattice (𝔹, (∧))
import Util (Endo, type (×), (×), type (+), (!), absurd, error)

type Op a = a × 𝔹 -> Val 𝔹
type MatrixRep a = Array (Array (Val a)) × (Int × a) × (Int × a)

data Val a =
   Int a Int |
   Float a Number |
   Str a String |
   Constr a Ctr (List (Val a)) |
   Matrix a (MatrixRep a) |
   Primitive  (Val 𝔹 -> Val 𝔹)

instance showVal :: Show (Val Boolean) where
   show (Int α n)       = show n <> "_" <> show α
   show (Float α n)     = show n <> "_" <> show α
   show (Str α str)     = show str <> "_" <> show α
   show (Constr _ _ _)  = error "todo"
   show (Matrix _ _)    = error "todo"
   show (Primitive op)  = error "todo"

getα :: Val 𝔹 -> 𝔹
getα (Int α _)       = α
getα (Float α _)     = α
getα (Str α _)       = α
getα (Constr α _ _)  = α
getα _         = error absurd

setα :: 𝔹 -> Endo (Val 𝔹)
setα α (Int _ n)        = Int α n
setα α (Float _ n)      = Float α n
setα α (Str _ str)      = Str α str
setα α (Constr _ c vs)  = Constr α c vs
setα _ _                = error absurd

class To a where
   to :: Val 𝔹 -> a × 𝔹

class From a where
   from :: a × 𝔹 -> Val 𝔹

instance fromVal :: From (Val Boolean) where
   from (v × α) = setα α v

instance toInt :: To Int where
   to (Int α n)   = n × α
   to _           = error "Int expected"

instance fromInt :: From Int where
   from (n × α) = Int α n

instance fromNumber :: From Number where
   from (n × α) = Float α n

instance toString :: To String where
   to (Str α str) = str × α
   to _           = error "Str expected"

instance fromString :: From String where
   from (str × α) = Str α str

instance toIntOrNumber :: To (Int + Number) where
   to (Int α n)    = Left n × α
   to (Float α n)  = Right n × α
   to _            = error "Int or Float expected"

instance fromIntOrNumber :: From (Int + Number) where
   from (Left n × α)    = Int α n
   from (Right n × α)   = Float α n

instance toIntOrNumberOrString :: To (Either (Either Int Number) String) where
   to (Int α n)   = Left (Left n) × α
   to (Float α n) = Left (Right n) × α
   to (Str α n)   = Right n × α
   to _           = error "Int, Float or Str expected"

instance toIntAndInt :: To (Int × Boolean × (Int × Boolean)) where
   to (Constr α c (v : v' : Nil)) | c == cPair  = to v × to v' × α
   to _                                         = error "Pair expected"

instance toMatrixRep :: To (Array (Array (Val Boolean)) × (Int × Boolean) × (Int × Boolean)) where
   to (Matrix α (vss × i × j))   = vss × i × j × α
   to _                          = error "Matrix expected"

from1 :: forall a b . To a => From b => (a × 𝔹 -> b × 𝔹) -> Val 𝔹
from1 op = Primitive (to >>> op >>> from)

from2 :: forall a b c . To a => To b => From c => (a × 𝔹 -> b × 𝔹 -> c × 𝔹) -> Val 𝔹
from2 op = Primitive (to >>> op >>> from1)

apply :: Val 𝔹 -> Val 𝔹 -> Val 𝔹
apply (Primitive op)   = op
apply _                = error absurd

depends :: forall a b . (a -> b) -> a × 𝔹 -> b × 𝔹
depends op (x × α) = op x × α

dependsBoth :: forall a b c . (a -> b -> c) -> a × 𝔹 -> b × 𝔹 -> c × 𝔹
dependsBoth op (x × α) (y × β) = x `op` y × (α ∧ β)

dependsNeither :: forall a b c . (a -> b -> c) -> a × 𝔹 -> b × 𝔹 -> c × 𝔹
dependsNeither op (x × _) (y × _) = x `op` y × true

class DependsBinary a b c where
   dependsNonZero :: (a -> b -> c) -> a × 𝔹 -> b × 𝔹 -> c × 𝔹

-- If both are false, we depend on the first.
instance dependsNonZeroInt :: DependsBinary Int Int a where
   dependsNonZero op (x × α) (y × β) =
      x `op` y × if x == 0 then α else if y == 0 then β else α ∧ β

instance dependsNonZeroNumber :: DependsBinary Number Number a where
   dependsNonZero op (x × α) (y × β) =
      x `op` y × if x == 0.0 then α else if y == 0.0 then β else α ∧ β

instance dependsNonZeroIntOrNumber :: DependsBinary (Int + Number) (Int + Number) a where
   dependsNonZero op (x × α) (y × β) =
      x `op` y ×
      if x `((==) `union2'` (==))` (Left 0)
      then α
      else if y `((==) `union2'` (==))` (Left 0) then β else α ∧ β

instance fromBoolean :: From Boolean where
   from (true × α)   = Constr α cTrue Nil
   from (false × α)  = Constr α cFalse Nil

primitives :: Bindings Val 𝔹
primitives = foldl (:+:) Empty [
   -- some signatures are specified for clarity or to drive instance resolution
   -- PureScript's / and pow aren't defined at Int -> Int -> Number, so roll our own
   "+"         ↦ from2 (dependsBoth ((+) `union2` (+))),
   "-"         ↦ from2 (dependsBoth ((-) `union2` (-))),
   "*"         ↦ from2 (dependsNonZero ((*) `union2` (*))),
   "**"        ↦ from2 (dependsNonZero ((\x y -> toNumber x `pow` toNumber y) `union2'` pow)),
   "/"         ↦ from2 (dependsNonZero ((\x y -> toNumber x / toNumber y)  `union2'` (/))),
   "=="        ↦ from2 (dependsBoth ((==) `union2'` (==) `unionDisj` (==))),
   "/="        ↦ from2 (dependsBoth ((/=) `union2'` (/=) `unionDisj` (==))),
   "<"         ↦ from2 (dependsBoth ((<)  `union2'` (<)  `unionDisj` (==))),
   ">"         ↦ from2 (dependsBoth ((>)  `union2'` (>)  `unionDisj` (==))),
   "<="        ↦ from2 (dependsBoth ((<=) `union2'` (<=) `unionDisj` (==))),
   ">="        ↦ from2 (dependsBoth ((>=) `union2'` (>=) `unionDisj` (==))),
   "++"        ↦ from2 (dependsBoth ((<>) :: String -> String -> String)),
   ":"         ↦ Constr false cCons Nil,
   "!"         ↦ from2 (dependsNeither matrixLookup),
   "ceiling"   ↦ from1 (depends ceil),
   "debugLog"  ↦ from1 (depends debugLog),
   "dims"      ↦ from1 dims,
   "div"       ↦ from2 (dependsNonZero (div :: Int -> Int -> Int)),
   "error"     ↦ from1 (depends  (error :: String -> Boolean)),
   "floor"     ↦ from1 (depends floor),
   "log"       ↦ from1 (depends ((toNumber >>> log) `union` log)),
   "numToStr"  ↦ from1 (depends (show `union` show))
]

debugLog :: Val 𝔹 -> Val 𝔹
debugLog x = trace x (const x)

dims :: (Array (Array (Val 𝔹)) × (Int × Int)) × 𝔹 -> (Val 𝔹 × Val 𝔹) × 𝔹
dims = error "todo"

matrixLookup :: MatrixRep 𝔹 -> (Int × 𝔹) × (Int × 𝔹) -> Val 𝔹
matrixLookup (vss × _ × _) (i × _ × (j × _)) = vss!(i - 1)!(j - 1)

-- Could improve this a bit with some type class shenanigans, but not straightforward.
union :: forall a . (Int -> a) -> (Number -> a) -> Int + Number -> a
union f _ (Left x)   = f x
union _ f (Right x)  = f x

union2 :: (Int -> Int -> Int) -> (Number -> Number -> Number) -> Int + Number -> Int + Number -> Int + Number
union2 f _ (Left x) (Left y)     = Left $ f x y
union2 _ f (Left x) (Right y)    = Right $ f (toNumber x) y
union2 _ f (Right x) (Right y)   = Right $ f x y
union2 _ f (Right x) (Left y)    = Right $ f x (toNumber y)

union2' :: forall a . (Int -> Int -> a) -> (Number -> Number -> a) -> Int + Number -> Int + Number -> a
union2' f _ (Left x) (Left y)    = f x y
union2' _ f (Left x) (Right y)   = f (toNumber x) y
union2' _ f (Right x) (Right y)  = f x y
union2' _ f (Right x) (Left y)   = f x (toNumber y)

unionDisj :: forall a b . (b -> b -> a) -> (String -> String -> a) -> b + String -> b + String -> a
unionDisj f _ (Left x) (Left y)   = f x y
unionDisj _ _ (Left _) (Right _)  = error "Non-uniform argument types"
unionDisj _ f (Right x) (Right y) = f x y
unionDisj _ _ (Right _) (Left _)  = error "Non-uniform argument types"

testPrim :: Val 𝔹
testPrim = apply (apply (from2 (dependsNonZero ((*) `union2` (*)))) (Int false 0)) (Int true 0)
