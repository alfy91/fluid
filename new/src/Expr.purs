module Expr where

import Prelude hiding (join)
import Data.List (List)
import Bindings (Var)
import Selected (Selected(..))

data Def = Def Var Expr
data RecDef = RecDef Var (Elim Expr)
type RecDefs = List RecDef

data RawExpr =
   Var Var |
   Op Var |
   Int Int |
   True | False |
   Pair Expr Expr |
   Nil | Cons Expr Expr |
   Lambda (Elim Expr) |
   App Expr Expr |
   BinaryApp Expr Var Expr |
   Match Expr (Elim Expr) |
   Let Def Expr |
   Letrec RecDefs Expr

data Expr = Expr Selected RawExpr

expr :: RawExpr -> Expr
expr r = Expr Bot r

data Elim k =
   ElimVar Var k |
   ElimBool { true :: k, false :: k } |
   ElimPair (Elim (Elim k)) |
   ElimList { nil :: k, cons :: Elim (Elim k) }

instance elimFunctor :: Functor Elim where
   map f (ElimVar x κ) = ElimVar x (f κ)
   map f (ElimBool { true: κ, false: κ' }) = ElimBool { true: f κ, false: f κ' }
   map f (ElimPair σ) = ElimPair $ map (map f) σ
   map f (ElimList { nil: κ, cons: σ }) = ElimList { nil: f κ, cons: map (map f) σ }

data Module = Module (List Def)
