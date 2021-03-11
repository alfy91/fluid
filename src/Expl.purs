module Expl where

import Data.List (List)
import Bindings (Var)
import DataType (Ctr)
import Expr (Elim, RecDefs)
import Util (type (×))
import Val (Env, PrimOp, Val)

data VarDef a = VarDef (Match a) (Expl a)

-- Easier to store environments than contexts in our setting. We also record values in some cases, which should
-- be assumed to be "unannotated" (= annotated with false).
data Expl a =
   Var (Env a) Var |
   Op (Env a) Var |
   Int (Env a) Int |
   Float (Env a) Number |
   Str (Env a) String |
   Constr (Env a) Ctr (List (Expl a)) |
   Matrix (Array (Array (Expl a))) (Var × Var) (Int × Int) (Expl a) |
   Lambda (Env a) (Elim a) |
   App (Expl a × Env a × RecDefs a × Elim a) (Expl a) (Match a) (Expl a) |
   AppPrim (Expl a × PrimOp) (Expl a × Val a) |
   AppConstr (Expl a × Ctr × Int) (Expl a × Val a) | -- record how many arguments supplied prior to this one
   Let (VarDef a) (Expl a) |
   LetRec (RecDefs a) (Expl a)

-- Constructor matches store the non-matched constructors too, because we tolerate partial eliminators
-- and need hole expansion to be be defined for those too.
data Match a =
   MatchVar Var |
   MatchVarAnon (Val a) |
   MatchConstr Ctr (List (Match a)) (List Ctr)
