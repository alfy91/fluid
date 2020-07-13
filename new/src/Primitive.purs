module Primitive where

import Prelude hiding (apply, append, map)
import Data.Foldable (foldl)
import Data.List (List(..), (:), snoc)
import Data.List as L
import Data.Map (Map, fromFoldable, toUnfoldable, singleton)
import Debug.Trace (trace) as T
import Text.Parsing.Parser.Expr (Assoc(..))
import DataType (cTrue, cNil, cCons, cFalse, cMany, Ctr(..))
import Pretty (pretty)
import Lattice (𝔹, (∧))
import Util (type (×), (×), error, fromJust)
import Expr as E
import Expr (Expr(..), Elim(..), Cont(..), Var, expr)
import Val (Env(..), Primitive(..), Val(..), (:+:),  (↦), val)
import Val (RawVal(..)) as V


trace s a = T.trace (pretty s) $ \_-> a
trace' s a = T.trace  s $ \_-> a

-- name in user land, precedence 0 to 9 (similar to Haskell 98), associativity
type OpDef = {
   op    :: Var,
   prec  :: Int,
   assoc :: Assoc
}

opDef :: Var -> Int -> Assoc -> Var × OpDef
opDef op prec assoc = op × { op, prec, assoc }

-- Syntactic information only. No guarantee that any of these will be defined.
opDefs :: Map String OpDef
opDefs = fromFoldable [
   opDef "*"   7 AssocLeft,
   opDef "+"   6 AssocLeft,
   opDef "-"   6 AssocLeft,
   opDef ":"   6 AssocRight,
   opDef "=="  4 AssocNone,
   opDef "/="  4 AssocNone,
   opDef "<"   4 AssocLeft,
   opDef ">"   4 AssocLeft,
   opDef "<="  4 AssocLeft,
   opDef ">="  4 AssocLeft
]

class ToList a where
   toList :: a -> List a

class FromList a where
   fromList :: List a -> a

instance exprToList :: ToList (Expr Boolean) where
   toList (Expr a (E.Constr (Ctr ":") (e:es:Nil))) = (e:toList es)
   toList (Expr a (E.Constr (Ctr "Nil") Nil)) = Nil
   toList e = let k = trace' "toList error: " (trace e 0) in error "expected list expression"

instance exprFromList :: FromList (Expr Boolean) where
   fromList (x:xs) = expr $ (E.Constr (Ctr ":") (x:fromList xs:Nil))
   fromList Nil    = expr $ E.Constr (Ctr "Nil") Nil

-- Enforce primitive argument types.
class To a where
   to :: Val 𝔹 -> a

class From a where
   from :: a -> Val 𝔹

instance toInt :: To Int where
   to (Val _ (V.Int n)) = n
   to _ = error "Integer expected"

instance fromInt :: From Int where
   from = V.Int >>> val

true_ :: Val 𝔹
true_ = val $ V.Constr cTrue Nil

false_ :: Val 𝔹
false_ = val $ V.Constr cFalse Nil

instance fromBoolean :: From Boolean where
   from b = if b then true_ else false_

instance fromString :: From String where
   from = V.Str >>> val

instance fromIntOp :: From a => From (Int -> a) where
   from op = val $ V.Primitive $ IntOp $ op >>> from

apply :: Primitive -> Val 𝔹 -> Val 𝔹
apply (IntOp op) = op <<< to

apply_fwd :: Primitive -> 𝔹 -> Val 𝔹 -> Val 𝔹
apply_fwd φ α v@(Val α' _) =
   Val (α ∧ α') u where Val _ u = apply φ v

primitives :: Env 𝔹
primitives = foldl (:+:) Empty [
   -- need to instantiate the corresponding PureScript primitive at a concrete type
   "+"         ↦ from   ((+)  :: Int -> Int -> Int),
   "-"         ↦ from   ((-)  :: Int -> Int -> Int),
   "*"         ↦ from   ((*)  :: Int -> Int -> Int),
   "div"       ↦ from   (div  :: Int -> Int -> Int),
   "=="        ↦ from   ((==) :: Int -> Int -> Boolean),
   "/="        ↦ from   ((/=) :: Int -> Int -> Boolean),
   "<"         ↦ from   ((<)  :: Int -> Int -> Boolean),
   ">"         ↦ from   ((>)  :: Int -> Int -> Boolean),
   "<="        ↦ from   ((<=) :: Int -> Int -> Boolean),
   ">="        ↦ from   ((>=) :: Int -> Int -> Boolean),
   "intToStr"  ↦ from   (show :: Int -> String)
]