module Primitive where

import Partial.Unsafe (unsafePartial)
import Prelude hiding (absurd, apply)
import Data.Either (Either(..))
import Data.Foldable (foldl)
import Data.Int (ceil, floor, toNumber)
import Data.List (List(..), (:))
import Data.Map (Map, fromFoldable)
import Data.Profunctor.Choice ((|||))
import Data.Tuple (fst)
import Debug.Trace (trace)
import Math (log, pow)
import Text.Parsing.Parser.Expr (Assoc(..))
import Bindings (Bindings(..), Var, (:+:), (↦))
import DataType (cCons, cFalse, cPair, cTrue)
import Lattice (𝔹, (∧))
import Util (type (×), (×), type (+), (!), (≜), absurd, assert, error, unsafeUpdateAt)
import Val (Env, MatrixRep, PrimOp(..), Val(..))

-- name in user land, precedence 0 from 9 (similar to Haskell 98), associativity
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

-- Mediates between a Val, and its underlying data, where "from" resembles pattern-matching, and "to" resembles
-- construction. The annotation associated with the underlying data is the analogue (for primitives) of the
-- annotation argument to eval (and returned by pattern-matching) controlling whether construction is permitted.
class ToFrom a where
   to :: a × 𝔹 -> Val 𝔹
   from :: Val 𝔹 -> a × 𝔹          -- only defined for non-holes
   expand :: a -> Val 𝔹            -- use just enough information from supplied value to construct an argument to 'from'

from_fwd :: forall a . ToFrom a => Val 𝔹 × a -> a × 𝔹
from_fwd (Hole × v') = from (expand v')
from_fwd (v × _)     = from v

instance toFromVal :: ToFrom (Val Boolean) where
   to = fst             -- construction rights not required
   from = (_ × true)    -- construction rights always provided
   expand = identity

instance toFromInt :: ToFrom Int where
   from (Int α n)   = n × α
   from _           = error "Int expected"

   to (n × α) = Int α n
   expand = Int false

instance toFromNumber :: ToFrom Number where
   from (Float α n) = n × α
   from _           = error "Float expected"

   to (n × α) = Float α n
   expand = Float false

instance toFromString :: ToFrom String where
   from (Str α str) = str × α
   from _           = error "Str expected"

   to (str × α) = Str α str
   expand = Str false

instance toFromIntOrNumber :: ToFrom (Int + Number) where
   to (Left n × α)   = Int α n
   to (Right n × α)  = Float α n

   from (Int α n)    = Left n × α
   from (Float α n)  = Right n × α
   from _            = error "Int or Float expected"

   expand (Left n)  = Int false n
   expand (Right n) = Float false n

instance toFromIntOrNumberOrString :: ToFrom (Either (Either Int Number) String) where
   to (Left (Left n) × α)  = Int α n
   to (Left (Right n) × α) = Float α n
   to (Right str × α)      = Str α str

   from (Int α n)   = Left (Left n) × α
   from (Float α n) = Left (Right n) × α
   from (Str α str) = Right str × α
   from _           = error "Int, Float or Str expected"

   expand (Left (Left n))    = Int false n
   expand (Left (Right n))   = Float false n
   expand (Right str)        = Str false str

instance toFromIntAndInt :: ToFrom (Int × Boolean × (Int × Boolean)) where
   to (nβ × mβ' × α) = Constr α cPair (to nβ : to mβ' : Nil)

   from (Constr α c (v : v' : Nil)) | c == cPair  = from v × from v' × α
   from _                                         = error "Pair expected"

   expand _ = Constr false cPair (Hole : Hole : Nil)

instance toFromMatrixRep :: ToFrom (Array (Array (Val Boolean)) × (Int × Boolean) × (Int × Boolean)) where
   from (Matrix α r) = r × α
   from _            = error "Matrix expected"

   to (r × α) = Matrix α r
   expand (vss × (i × _) × (j × _)) = Matrix false (((<$>) (const Hole) <$> vss) × (i × false) × (j × false))

instance toFromPair :: ToFrom (Val Boolean × Val Boolean) where
   from (Constr α c (v : v' : Nil)) | c == cPair   = v × v' × α
   from _                                          = error "Pair expected"

   to (v × v' × α) = Constr α cPair (v : v' : Nil)
   expand _ = Constr false cPair (Hole : Hole : Nil)

instance toFromBoolean :: ToFrom Boolean where
   from (Constr α c Nil)
      | c == cTrue   = true × α
      | c == cFalse  = false × α
   from _ = error absurd

   to (true × α)   = Constr α cTrue Nil
   to (false × α)  = Constr α cFalse Nil

   expand = \_ -> error "todo"

class IsZero a where
   isZero :: a -> Boolean

instance isZeroInt :: IsZero Int where
   isZero = ((==) 0)

instance isZeroNumber :: IsZero Number where
   isZero = ((==) 0.0)

instance isZeroEither :: (IsZero a, IsZero b) => IsZero (a + b) where
   isZero = isZero ||| isZero

unary :: forall a b . ToFrom a => ToFrom b => UnarySpec a b -> Val 𝔹
unary { fwd, bwd } = flip Primitive Nil $ PrimOp {
   arity: 1,
   op: unsafePartial apply,
   op_fwd: unsafePartial apply_fwd,
   op_bwd: unsafePartial apply_bwd
}
   where
   apply :: Partial => List (Val 𝔹) {-[a]-} -> Val 𝔹 {-b-}
   apply (v : Nil) = to (fwd (from v))

   apply_fwd :: Partial => List (Val 𝔹 × Val 𝔹) {-[(a, a)]-} -> Val 𝔹 {-b-}
   apply_fwd (v × u : Nil) = to (fwd (from_fwd (v × fst (from u))))

   apply_bwd :: Partial => Val 𝔹 {-b-} -> List (Val 𝔹) {-[a]-} -> List (Val 𝔹) {-[a]-}
   apply_bwd v (v1 : Nil) = to v1' : Nil
      where v1' = bwd (from v) (fst (from v1))

binary :: forall a b c . ToFrom a => ToFrom b => ToFrom c => BinarySpec a b c -> Val 𝔹
binary { fwd, bwd } = flip Primitive Nil $ PrimOp {
   arity: 2,
   op: unsafePartial apply,
   op_fwd: unsafePartial apply_fwd,
   op_bwd: unsafePartial apply_bwd
}
   where
   apply :: Partial => List (Val 𝔹) {-[a, b]-} -> Val 𝔹 {-c-}
   apply (v : v' : Nil) = to (fwd (from v) (from v'))

   apply_fwd :: Partial => List (Val 𝔹 × Val 𝔹) {-[(a, a), (b, b)]-} -> Val 𝔹 {-c-}
   apply_fwd (v1 × u1 : v2 × u2 : Nil) = to (fwd (from_fwd (v1 × fst (from u1))) (from_fwd (v2 × fst (from u2))))

   apply_bwd :: Partial => Val 𝔹 {-c-} -> List (Val 𝔹) {-[a, b]-} -> List (Val 𝔹) {-[a, b]-}
   apply_bwd v (v1 : v2 : Nil) = to v1' : to v2' : Nil
      where v1' × v2' = bwd (from v) (fst (from v1) × fst (from v2))

type UnarySpec a b = {
   fwd :: a × 𝔹 -> b × 𝔹,
   bwd :: b × 𝔹 -> a -> a × 𝔹
}

type BinarySpec a b c = {
   fwd :: a × 𝔹 -> b × 𝔹 -> c × 𝔹,
   bwd :: c × 𝔹 -> a × b -> (a × 𝔹) × (b × 𝔹)
}

depends :: forall a b . (a -> b) -> UnarySpec a b
depends op = { fwd, bwd }
   where
   fwd (x × α)    = op x × α
   bwd (_ × α) x  = x × α

depends2 :: forall a b . ((a -> b) × (b -> a -> a)) -> UnarySpec a b
depends2 (f × g) = { fwd: f', bwd: g' }
   where
   f' (x × α)    = f x × α
   g' (y × α) x  = g y x × α

dependsBoth :: forall a b c . (a -> b -> c) -> BinarySpec a b c
dependsBoth op = { fwd, bwd }
   where
   fwd (x × α) (y × β) = x `op` y × (α ∧ β)
   bwd (_ × α) (x × y) = (x × α) × (y × α)

dependsBoth2 :: forall a b c . ((a -> b -> c) × (c -> a × b -> a × b)) -> BinarySpec a b c
dependsBoth2 (f × g) = { fwd: f', bwd: g' }
   where
   f' (x × α) (y × β) = f x y × (α ∧ β)
   g' (z × α) (x × y) = (x' × α) × (y' × α) where x' × y' = g z (x × y)

-- If both are zero, depend only on the first.
dependsZero :: forall a b . IsZero a => (a -> a -> b) -> BinarySpec a a b
dependsZero op = { fwd, bwd }
   where
   fwd :: a × 𝔹 -> a × 𝔹 -> b × 𝔹
   fwd (x × α) (y × β)
      | isZero x  = x `op` y × α
      | isZero y  = x `op` y × β
      | otherwise = x `op` y × (α ∧ β)
   bwd :: b × 𝔹 -> a × a -> (a × 𝔹) × (a × 𝔹)
   bwd (_ × α) (x × y)
      | isZero x  = (x × α) × (y × false)
      | isZero y  = (x × false) × (y × α)
      | otherwise = (x × α) × (y × α)

primitives :: Env 𝔹
primitives = foldl (:+:) Empty [
   -- some signatures are specified for clarity or to drive instance resolution
   -- PureScript's / and pow aren't defined at Int -> Int -> Number, so roll our own
   ":"         ↦ Constr false cCons Nil,
   "+"         ↦ binary (dependsBoth ((+) `union2` (+))),
   "-"         ↦ binary (dependsBoth ((-) `union2` (-))),
   "*"         ↦ binary (dependsZero ((*) `union2` (*))),
   "**"        ↦ binary (dependsZero ((\x y -> toNumber x `pow` toNumber y) `union2'` pow)),
   "/"         ↦ binary (dependsZero ((\x y -> toNumber x / toNumber y)  `union2'` (/))),
   "=="        ↦ binary (dependsBoth ((==) `union2'` (==) `unionDisj` (==))),
   "/="        ↦ binary (dependsBoth ((/=) `union2'` (/=) `unionDisj` (==))),
   "<"         ↦ binary (dependsBoth ((<)  `union2'` (<)  `unionDisj` (==))),
   ">"         ↦ binary (dependsBoth ((>)  `union2'` (>)  `unionDisj` (==))),
   "<="        ↦ binary (dependsBoth ((<=) `union2'` (<=) `unionDisj` (==))),
   ">="        ↦ binary (dependsBoth ((>=) `union2'` (>=) `unionDisj` (==))),
   "++"        ↦ binary (dependsBoth ((<>) :: String -> String -> String)),
   "!"         ↦ binary matrixLookup,
   "ceiling"   ↦ unary (depends ceil),
   "debugLog"  ↦ unary (depends debugLog),
   "dims"      ↦ unary dims,
   "div"       ↦ binary (dependsZero (div :: Int -> Int -> Int)),
   "error"     ↦ unary (depends (error :: String -> Val 𝔹)),
   "floor"     ↦ unary (depends floor),
   "log"       ↦ unary (depends ((toNumber >>> log) `union` log)),
   "numToStr"  ↦ unary (depends (show `union` show))
]

debugLog :: Val 𝔹 -> Val 𝔹
debugLog x = trace x (const x)

dims :: UnarySpec (MatrixRep 𝔹) (Val 𝔹 × Val 𝔹)
dims = depends2 (fwd × bwd)
   where
   fwd :: MatrixRep 𝔹 -> Val 𝔹 × Val 𝔹
   fwd (_ × (i × β) × (j × β')) = Int β i × Int β' j

   bwd :: Val 𝔹 × Val 𝔹 -> MatrixRep 𝔹 -> MatrixRep 𝔹
   bwd (Int β i' × Int β' j') (vss × (i × _) × (j × _))  = vss × ((i ≜ i') × β) × ((j ≜ j') × β')
   bwd (_ × _) _                                         = error absurd

-- Annotation on first arg to bwd is always true, and on return value of fwd is irrelevant.
matrixLookup :: BinarySpec (MatrixRep 𝔹) ((Int × 𝔹) × (Int × 𝔹)) (Val 𝔹)
matrixLookup = { fwd, bwd }
   where
   fwd :: MatrixRep 𝔹 × 𝔹 -> (Int × 𝔹) × (Int × 𝔹) × 𝔹 -> Val 𝔹 × 𝔹
   fwd ((vss × _ × _) × _) ((i × _) × (j × _) × _) = vss!(i - 1)!(j - 1) × false

   bwd :: Val 𝔹 × 𝔹 -> MatrixRep 𝔹 × ((Int × 𝔹) × (Int × 𝔹)) -> (MatrixRep 𝔹 × 𝔹) × ((Int × 𝔹) × (Int × 𝔹) × 𝔹)
   bwd (v × α) (vss × (i' × _) × (j' × _) × ((i × _) × (j × _))) =
      assert α $
      (vss'' × (i' × false) × (j' × false) × false) × ((i × false) × (j × false) × false)
      where vss'  = (<$>) (const Hole) <$> vss
            vs_i  = vss'!(i - 1)
            vss'' = unsafeUpdateAt (i - 1) (unsafeUpdateAt (j - 1) v vs_i) vss'

-- Could improve this a bit with some type class shenanigans, but not straightforward.
union :: forall a . (Int -> a) -> (Number -> a) -> Int + Number -> a
union f _ (Left x)   = f x
union _ f (Right x)  = f x

union2 :: (Int -> Int -> Int) -> (Number -> Number -> Number) -> Int + Number -> Int + Number -> Int + Number
union2 f _ (Left x) (Left y)     = Left (f x y)
union2 _ f (Left x) (Right y)    = Right (f (toNumber x) y)
union2 _ f (Right x) (Right y)   = Right (f x y)
union2 _ f (Right x) (Left y)    = Right (f x (toNumber y))

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
