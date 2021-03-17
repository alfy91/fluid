module Primitive.Defs where

import Prelude hiding (absurd, div)
import Prelude (div) as P
import Data.Foldable (foldl)
import Data.Int (ceil, floor, toNumber)
import Data.List (List(..))
import Data.Map (Map, fromFoldable)
import Debug.Trace (trace)
import Math (log, pow) as M
import Text.Parsing.Parser.Expr (Assoc(..))
import Bindings (Bindings(..), (:+:), (↦))
import DataType (cCons)
import Lattice (𝔹)
import Primitive (
   Binary, OpDef, Unary,
   binary, binaryZero, constr, constr_bwd, opDef, unary, union, union1, unionStr, withInverse1, withInverse2
)
import Util (type (×), (×), type (+), (!), error, unsafeUpdateAt)
import Val (Env, MatrixRep, Val(..))

-- Syntactic information only. No requirement that any of these be defined.
opDefs :: Map String OpDef
opDefs = fromFoldable [
   opDef "!"   8 AssocLeft,
   opDef "**"  8 AssocRight,
   opDef "*"   7 AssocLeft,
   opDef "/"   7 AssocLeft,
   opDef "+"   6 AssocLeft,
   opDef "-"   6 AssocLeft,
   opDef ":"   6 AssocRight,
   opDef "++"  5 AssocRight,
   opDef "=="  4 AssocNone,
   opDef "/="  4 AssocNone,
   opDef "<"   4 AssocLeft,
   opDef ">"   4 AssocLeft,
   opDef "<="  4 AssocLeft,
   opDef ">="  4 AssocLeft
]

primitives :: Env 𝔹
primitives = foldl (:+:) Empty [
   ":"         ↦ Constr false cCons Nil,

   "+"         ↦ binary (withInverse2 plus),
   "-"         ↦ binary (withInverse2 minus),
   "*"         ↦ binaryZero (withInverse2 times),
   "**"        ↦ binaryZero (withInverse2 pow),
   "/"         ↦ binaryZero (withInverse2 divide),
   "=="        ↦ binary (withInverse2 equals),
   "/="        ↦ binary (withInverse2 notEquals),
   "<"         ↦ binary (withInverse2 lessThan),
   ">"         ↦ binary (withInverse2 greaterThan),
   "<="        ↦ binary (withInverse2 lessThanEquals),
   ">="        ↦ binary (withInverse2 greaterThanEquals),
   "++"        ↦ binary (withInverse2 concat),
   "!"         ↦ binary matrixLookup,
   "div"       ↦ binaryZero (withInverse2 div),

   "ceiling"   ↦ unary (withInverse1 ceil),
   "debugLog"  ↦ unary (withInverse1 debugLog),
   "dims"      ↦ unary dims,
   "error"     ↦ unary (withInverse1 error_),
   "floor"     ↦ unary (withInverse1 floor),
   "log"       ↦ unary (withInverse1 log),
   "numToStr"  ↦ unary (withInverse1 numToStr)
]

debugLog :: Val 𝔹 -> Val 𝔹
debugLog x = trace x (const x)

error_ :: String -> Val 𝔹
error_ = error

dims :: Unary (MatrixRep 𝔹) (Val 𝔹 × Val 𝔹)
dims = { fwd, bwd }
   where
   fwd :: MatrixRep 𝔹 -> Val 𝔹 × Val 𝔹
   fwd (_ × i × j) = constr i × constr j

   bwd :: Val 𝔹 × Val 𝔹 -> MatrixRep 𝔹 -> MatrixRep 𝔹
   bwd (u × v) (vss × _ × _) = vss × constr_bwd u × constr_bwd v

-- Unfortunately the primitives infrastructure doesn't generalise to "deep" pattern-matching/construction. Here
-- non-neededness of matrix bounds/indices should arise automtically because construction rights are not required.
matrixLookup :: Binary (MatrixRep 𝔹) ((Int × 𝔹) × (Int × 𝔹)) (Val 𝔹)
matrixLookup = { fwd, bwd }
   where
   fwd :: MatrixRep 𝔹 -> (Int × 𝔹) × (Int × 𝔹) -> Val 𝔹
   fwd (vss × _ × _) ((i × _) × (j × _)) = vss!(i - 1)!(j - 1)

   bwd :: Val 𝔹 -> MatrixRep 𝔹 × ((Int × 𝔹) × (Int × 𝔹)) -> MatrixRep 𝔹 × ((Int × 𝔹) × (Int × 𝔹))
   bwd v (vss × (i' × _) × (j' × _) × ((i × _) × (j × _))) =
       (vss'' × (i' × false) × (j' × false)) × ((i × false) × (j × false))
       where vss'  = (<$>) (const Hole) <$> vss
             vs_i  = vss'!(i - 1)
             vss'' = unsafeUpdateAt (i - 1) (unsafeUpdateAt (j - 1) v vs_i) vss'

plus :: Int + Number -> Int + Number -> Int + Number
plus = (+) `union` (+)

minus :: Int + Number -> Int + Number -> Int + Number
minus = (-) `union` (-)

times :: Int + Number -> Int + Number -> Int + Number
times = (*) `union` (*)

-- PureScript's / and pow aren't defined at Int -> Int -> Number, so roll our own
pow :: Int + Number -> Int + Number -> Int + Number
pow = (\x y -> toNumber x `M.pow` toNumber y) `union` M.pow

divide :: Int + Number -> Int + Number -> Int + Number
divide = (\x y -> toNumber x / toNumber y)  `union` (/)

div :: Int -> Int -> Int
div = P.div

equals :: Int + Number + String -> Int + Number + String -> Boolean
equals = (==) `union` (==) `unionStr` (==)

notEquals :: Int + Number + String -> Int + Number + String -> Boolean
notEquals = (/=) `union` (/=) `unionStr` (/=)

lessThan :: Int + Number + String -> Int + Number + String -> Boolean
lessThan = (<)  `union` (<)  `unionStr` (<)

greaterThan :: Int + Number + String -> Int + Number + String -> Boolean
greaterThan = (>)  `union` (>)  `unionStr` (>)

lessThanEquals :: Int + Number + String -> Int + Number + String -> Boolean
lessThanEquals = (<=) `union` (<=) `unionStr` (<=)

greaterThanEquals :: Int + Number + String -> Int + Number + String -> Boolean
greaterThanEquals = (>=) `union` (>=) `unionStr` (>=)

concat :: String -> String -> String
concat = (<>)

numToStr :: Int + Number -> String
numToStr = show `union1` show

log :: Int + Number -> Number
log = (toNumber >>> M.log) `union1` M.log
