module DesugarFwd where

import Prelude hiding (absurd, otherwise)

import Data.Either (Either(..))
import Data.Foldable (foldM)
import Data.Function (applyN, on)
import Data.List (List(..), (:), (\\), length, sortBy)
import Data.List (singleton) as L
import Data.List.NonEmpty (NonEmptyList(..), groupBy, head, toList)
import Data.NonEmpty ((:|))
import Data.Set (toUnfoldable) as S
import Data.Traversable (traverse)
import Data.Tuple (fst, snd, uncurry)
import Bindings (Bind, (↦), keys, varAnon)
import Dict (Dict, asSingletonMap)
import Dict (fromFoldable, singleton) as D
import DataType (Ctr, arity, checkArity, ctrs, cCons, cFalse, cNil, cTrue, dataTypeFor)
import Expr (Cont(..), Elim(..), asElim)
import Expr (Expr(..), Module(..), RecDefs, VarDef(..)) as E
import Lattice (𝔹, maybeJoin)
import SExpr (Branch, Clause, Expr(..), ListRestPattern(..), ListRest(..), Module(..), Pattern(..), VarDefs, VarDef(..), RecDefs, Qualifier(..))
import Util (MayFail, type (+), type (×), (×), absurd, error, successful)

desugarFwd :: Expr 𝔹 -> MayFail (E.Expr 𝔹)
desugarFwd = exprFwd

desugarModuleFwd :: Module 𝔹 -> MayFail (E.Module 𝔹)
desugarModuleFwd = moduleFwd

enil :: 𝔹 -> E.Expr 𝔹
enil α = E.Constr α cNil Nil

econs :: 𝔹 -> E.Expr 𝔹 -> E.Expr 𝔹 -> E.Expr 𝔹
econs α e e' = E.Constr α cCons (e : e' : Nil)

elimBool :: Cont 𝔹 -> Cont 𝔹 -> Elim 𝔹
elimBool κ κ' = ElimConstr (D.fromFoldable [ cTrue × κ, cFalse × κ' ])

-- Surface language supports "blocks" of variable declarations; core does not.
moduleFwd :: Module 𝔹 -> MayFail (E.Module 𝔹)
moduleFwd (Module ds) = E.Module <$> traverse varDefOrRecDefsFwd (join (desugarDefs <$> ds))
   where
   varDefOrRecDefsFwd :: VarDef 𝔹 + RecDefs 𝔹 -> MayFail (E.VarDef 𝔹 + E.RecDefs 𝔹)
   varDefOrRecDefsFwd (Left d) = Left <$> varDefFwd d
   varDefOrRecDefsFwd (Right xcs) = Right <$> recDefsFwd xcs

   desugarDefs :: VarDefs 𝔹 + RecDefs 𝔹 -> List (VarDef 𝔹 + RecDefs 𝔹)
   desugarDefs (Left ds') = Left <$> toList ds'
   desugarDefs (Right δ) = pure (Right δ)

varDefFwd :: VarDef 𝔹 -> MayFail (E.VarDef 𝔹)
varDefFwd (VarDef π s) = E.VarDef <$> patternFwd π (ContNone :: Cont 𝔹) <*> exprFwd s

varDefsFwd :: VarDefs 𝔹 × Expr 𝔹 -> MayFail (E.Expr 𝔹)
varDefsFwd (NonEmptyList (d :| Nil) × s) =
   E.Let <$> varDefFwd d <*> exprFwd s
varDefsFwd (NonEmptyList (d :| d' : ds) × s) =
   E.Let <$> varDefFwd d <*> varDefsFwd (NonEmptyList (d' :| ds) × s)

-- In the formalism, "group by name" is part of the syntax.
-- cs desugar_fwd σ
recDefsFwd :: RecDefs 𝔹 -> MayFail (E.RecDefs 𝔹)
recDefsFwd xcs = D.fromFoldable <$> traverse recDefFwd xcss
   where
   xcss = groupBy (eq `on` fst) xcs :: NonEmptyList (NonEmptyList (Clause 𝔹))

recDefFwd :: NonEmptyList (Clause 𝔹) -> MayFail (Bind (Elim 𝔹))
recDefFwd xcs = (fst (head xcs) ↦ _) <$> branchesFwd_curried (snd <$> xcs)

-- s desugar_fwd e
exprFwd :: Expr 𝔹 -> MayFail (E.Expr 𝔹)
exprFwd (Var x) = pure (E.Var x)
exprFwd (Op op) = pure (E.Op op)
exprFwd (Int α n) = pure (E.Int α n)
exprFwd (Float α n) = pure (E.Float α n)
exprFwd (Str α s) = pure (E.Str α s)
exprFwd (Constr α c ss) = E.Constr α c <$> traverse exprFwd ss
exprFwd (Record α xss) = E.Record α <$> D.fromFoldable <$> traverse (traverse exprFwd) xss
exprFwd (Matrix α s (x × y) s') = E.Matrix α <$> exprFwd s <@> x × y <*> exprFwd s'
exprFwd (Lambda bs) = E.Lambda <$> branchesFwd_curried bs
exprFwd (Project s x) = E.Project <$> exprFwd s <@> x
exprFwd (App s1 s2) = E.App <$> exprFwd s1 <*> exprFwd s2
exprFwd (BinaryApp s1 op s2) = E.App <$> (E.App (E.Op op) <$> exprFwd s1) <*> exprFwd s2
exprFwd (MatchAs s bs) = E.App <$> (E.Lambda <$> branchesFwd_uncurried bs) <*> exprFwd s
exprFwd (IfElse s1 s2 s3) = do
   e2 <- exprFwd s2
   e3 <- exprFwd s3
   E.App (E.Lambda (elimBool (ContExpr e2) (ContExpr e3))) <$> exprFwd s1
exprFwd (ListEmpty α) = pure (enil α)
exprFwd (ListNonEmpty α s l) = econs α <$> exprFwd s <*> listRestFwd l
exprFwd (ListEnum s1 s2) = E.App <$> ((E.App (E.Var "enumFromTo")) <$> exprFwd s1) <*> exprFwd s2
-- | List-comp-done
exprFwd (ListComp _ s_body (NonEmptyList (Guard (Constr α2 c Nil) :| Nil))) | c == cTrue =
   econs α2 <$> exprFwd s_body <@> enil α2
-- | List-comp-last
exprFwd (ListComp α s_body (NonEmptyList (q :| Nil))) =
   exprFwd (ListComp α s_body (NonEmptyList (q :| Guard (Constr α cTrue Nil) : Nil)))
-- | List-comp-guard
exprFwd (ListComp α s_body (NonEmptyList (Guard s :| q : qs))) = do
   e <- exprFwd (ListComp α s_body (NonEmptyList (q :| qs)))
   E.App (E.Lambda (elimBool (ContExpr e) (ContExpr (enil α)))) <$> exprFwd s
-- | List-comp-decl
exprFwd (ListComp α s_body (NonEmptyList (Declaration (VarDef π s) :| q : qs))) = do
   e <- exprFwd (ListComp α s_body (NonEmptyList (q :| qs)))
   σ <- patternFwd π (ContExpr e :: Cont 𝔹)
   E.App (E.Lambda σ) <$> exprFwd s
-- | List-comp-gen
exprFwd (ListComp α s_body (NonEmptyList (Generator p s :| q : qs))) = do
   e <- exprFwd (ListComp α s_body (NonEmptyList (q :| qs)))
   σ <- patternFwd p (ContExpr e)
   E.App (E.App (E.Var "concatMap") (E.Lambda (asElim (totaliseFwd (ContElim σ) α)))) <$> exprFwd s
exprFwd (Let ds s) = varDefsFwd (ds × s)
exprFwd (LetRec xcs s) = E.LetRec <$> recDefsFwd xcs <*> exprFwd s

-- l desugar_fwd e
listRestFwd :: ListRest 𝔹 -> MayFail (E.Expr 𝔹)
listRestFwd (End α) = pure (enil α)
listRestFwd (Next α s l) = econs α <$> exprFwd s <*> listRestFwd l

-- ps, e desugar_fwd σ
patternsFwd :: NonEmptyList Pattern × Expr 𝔹 -> MayFail (Elim 𝔹)
patternsFwd (NonEmptyList (p :| Nil) × e) = branchFwd_uncurried p e
patternsFwd (NonEmptyList (p :| p' : ps) × e) =
   patternFwd p =<< ContExpr <$> E.Lambda <$> patternsFwd (NonEmptyList (p' :| ps) × e)

patternFwd :: Pattern -> Cont 𝔹 -> MayFail (Elim 𝔹)
patternFwd (PVar x) κ = pure (ElimVar x κ)
patternFwd (PConstr c ps) κ =
   checkArity c (length ps) *> (ElimConstr <$> D.singleton c <$> argPatternFwd (Left <$> ps) κ)
patternFwd (PRecord xps) κ = ElimRecord (keys xps) <$> recordPatternFwd (sortBy (flip compare `on` fst) xps) κ
patternFwd PListEmpty κ = pure (ElimConstr (D.singleton cNil κ))
patternFwd (PListNonEmpty p o) κ = ElimConstr <$> D.singleton cCons <$> argPatternFwd (Left p : Right o : Nil) κ

-- o, κ desugar_fwd σ
listRestPatternFwd :: ListRestPattern -> Cont 𝔹 -> MayFail (Elim 𝔹)
listRestPatternFwd PEnd κ = pure (ElimConstr (D.singleton cNil κ))
listRestPatternFwd (PNext p o) κ = ElimConstr <$> D.singleton cCons <$> argPatternFwd (Left p : Right o : Nil) κ

argPatternFwd :: List (Pattern + ListRestPattern) -> Cont 𝔹 -> MayFail (Cont 𝔹)
argPatternFwd Nil κ = pure κ
argPatternFwd (Left p : πs) κ = ContElim <$> (argPatternFwd πs κ >>= patternFwd p)
argPatternFwd (Right o : πs) κ = ContElim <$> (argPatternFwd πs κ >>= listRestPatternFwd o)

recordPatternFwd :: List (Bind Pattern) -> Cont 𝔹 -> MayFail (Cont 𝔹)
recordPatternFwd Nil κ = pure κ
recordPatternFwd (_ ↦ p : xps) κ = patternFwd p κ >>= ContElim >>> recordPatternFwd xps

branchFwd_uncurried :: Pattern -> Expr 𝔹 -> MayFail (Elim 𝔹)
branchFwd_uncurried p s = (ContExpr <$> exprFwd s) >>= patternFwd p

branchesFwd_curried :: NonEmptyList (Branch 𝔹) -> MayFail (Elim 𝔹)
branchesFwd_curried bs = do
   NonEmptyList (σ :| σs) <- traverse patternsFwd bs
   foldM maybeJoin σ σs

branchesFwd_uncurried :: NonEmptyList (Pattern × Expr 𝔹) -> MayFail (Elim 𝔹)
branchesFwd_uncurried bs = do
   NonEmptyList (σ :| σs) <- traverse (uncurry branchFwd_uncurried) bs
   foldM maybeJoin σ σs

totaliseFwd :: Cont 𝔹 -> 𝔹 -> Cont 𝔹
totaliseFwd ContNone _ = error absurd
totaliseFwd (ContExpr e) _ = ContExpr e
totaliseFwd (ContElim (ElimConstr m)) α = ContElim (ElimConstr (totaliseConstrFwd (c × totaliseFwd κ α) α))
   where
   c × κ = asSingletonMap m
totaliseFwd (ContElim (ElimRecord xs κ)) α = ContElim (ElimRecord xs (totaliseFwd κ α))
totaliseFwd (ContElim (ElimVar x κ)) α = ContElim (ElimVar x (totaliseFwd κ α))

-- Extend singleton branch to set of branches where any missing constructors have been mapped to the empty list,
-- using anonymous variables in any generated patterns.
totaliseConstrFwd :: Ctr × Cont 𝔹 -> 𝔹 -> Dict (Cont 𝔹)
totaliseConstrFwd (c × κ) α =
   let
      defaultBranch c' = c' × applyN (ContElim <<< ElimVar varAnon) (successful (arity c')) (ContExpr (enil α))
      cκs = defaultBranch <$> ((ctrs (successful (dataTypeFor c)) # S.toUnfoldable) \\ L.singleton c)
   in
      D.fromFoldable (c × κ : cκs)
