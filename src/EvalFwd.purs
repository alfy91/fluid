module EvalFwd where

import Prelude hiding (absurd)

import Data.Array (fromFoldable) as A
import Data.List (List(..), (:), length, range, singleton, zip)
import Data.Map (fromFoldable)
import Data.Profunctor.Strong ((***), (&&&), first, second)
import Data.Tuple (fst)
import Bindings (Bindings, (↦), find, key, val, varAnon)
import DataType (cPair)
import Expl (Expl(..), Match(..), VarDef(..)) as T
import Expl (Expl, Match)
import Expr (Cont(..), Elim(..), Expr(..), RecDefs, VarDef(..), asElim, asExpr)
import Lattice (𝔹, (∧), botOf, expand)
import Primitive (match_fwd) as P
import Util (type (×), (×), (!), absurd, assert, error, mustLookup, replicate, successful)
import Util.SnocList (SnocList(..), (:-))
import Util.SnocList (unzip, zip, zipWith) as S
import Val (Env, PrimOp(..), Val)
import Val (Val(..)) as V

matchFwd :: Val 𝔹 -> Elim 𝔹 -> Match 𝔹 -> Env 𝔹 × Cont 𝔹 × 𝔹
matchFwd v σ (T.MatchVar x) =
   case expand σ (ElimVar x (ContHole false)) of
      ElimVar _ κ -> (Lin :- x ↦ v) × κ × true
      _ -> error absurd
matchFwd _ σ (T.MatchVarAnon _) =
   case expand σ (ElimVar varAnon (ContHole false)) of
      ElimVar _ κ -> Lin × κ × true
      _ -> error absurd
matchFwd v σ (T.MatchConstr c ws cs) =
   case expand v (V.Constr false c (const (V.Hole false) <$> ws)) ×
        expand σ (ElimConstr (fromFoldable ((_ × ContHole false) <$> c : cs))) of
      V.Constr α _ vs × ElimConstr m ->
         (second (_ ∧ α)) (matchArgsFwd vs (mustLookup c m) ws)
      _ -> error absurd
matchFwd v σ (T.MatchRecord xws) =
   let xs = xws <#> key in
   case expand v (V.Record false (map (const (V.Hole false)) <$> xws)) ×
        expand σ (ElimRecord xs (ContHole false)) of
      V.Record α xvs × ElimRecord _ κ ->
         (second (_ ∧ α)) (matchRecordFwd xvs κ xws)
      _ -> error absurd

matchArgsFwd :: List (Val 𝔹) -> Cont 𝔹 -> List (Match 𝔹) -> Env 𝔹 × Cont 𝔹 × 𝔹
matchArgsFwd Nil κ Nil = Lin × κ × true
matchArgsFwd (v : vs) σ (w : ws) =
   let ρ × κ × α = matchFwd v (asElim σ) w in
   (first (ρ <> _) *** (_ ∧ α)) (matchArgsFwd vs κ ws)
matchArgsFwd _ _ _ = error absurd

matchRecordFwd :: Bindings (Val 𝔹) -> Cont 𝔹 -> Bindings (Match 𝔹) -> Env 𝔹 × Cont 𝔹 × 𝔹
matchRecordFwd Lin κ Lin = Lin × κ × true
matchRecordFwd (xvs :- x ↦ v) σ (xws :- x' ↦ w) | x == x' =
   let ρ × σ' × α = matchRecordFwd xvs σ xws in
   (first (ρ <> _) *** (_ ∧ α)) (matchFwd v (asElim σ') w)
matchRecordFwd _ _ _ = error absurd

closeDefsFwd :: Env 𝔹 -> RecDefs 𝔹 -> 𝔹 -> RecDefs 𝔹 -> Env 𝔹
closeDefsFwd _ _ _ Lin = Lin
closeDefsFwd ρ δ0 α (δ :- f ↦ σ) = closeDefsFwd ρ δ0 α δ :- f ↦ V.Closure ρ δ0 α σ

evalFwd :: Env 𝔹 -> Expr 𝔹 -> 𝔹 -> Expl 𝔹 -> Val 𝔹
evalFwd ρ e _ (T.Var _ x) =
   case expand e (Var x) of
      Var _ -> successful (find x ρ)
      _ -> error absurd
evalFwd ρ e _ (T.Op _ op) =
   case expand e (Op op) of
      Op _ -> successful (find op ρ)
      _ -> error absurd
evalFwd ρ e α' (T.Int _ n) =
   case expand e (Int false n) of
      Int α _ -> V.Int (α ∧ α') n
      _ -> error absurd
evalFwd ρ e α' (T.Float _ n) =
   case expand e (Float false n) of
      Float α _ -> V.Float (α ∧ α') n
      _ -> error absurd
evalFwd ρ e α' (T.Str _ str) =
   case expand e (Str false str) of
      Str α _ -> V.Str (α ∧ α') str
      _ -> error absurd
evalFwd ρ e α' (T.Record _ xts) =
   case expand e (Record false (map (const (Hole false)) <$> xts)) of
      Record α xes ->
         let xs × ts = xts <#> (key &&& val) # S.unzip
             es = xes <#> val
             vs = (\(e' × t) -> evalFwd ρ e' α' t) <$> S.zip es ts in
         V.Record (α ∧ α') (S.zipWith (↦) xs vs)
      _ -> error absurd
evalFwd ρ e α' (T.Constr _ c ts) =
   case expand e (Constr false c (const (Hole false) <$> ts)) of
      Constr α _ es ->
         V.Constr (α ∧ α') c ((\(e' × t) -> evalFwd ρ e' α' t) <$> zip es ts)
      _ -> error absurd
evalFwd ρ e α' (T.Matrix tss (x × y) (i' × j') t2) =
   case expand e (Matrix false (Hole false) (x × y) (Hole false)) of
      Matrix α e1 _ e2 ->
         case expand (evalFwd ρ e2 α' t2) (V.Constr false cPair (V.Hole false : V.Hole false : Nil)) of
            V.Constr _ c (v1 : v2 : Nil) ->
               let (i'' × β) × (j'' × β') = P.match_fwd (v1 × V.Int false i') × P.match_fwd (v2 × V.Int false j')
                   vss = assert (i'' == i' && j'' == j') $ A.fromFoldable $ do
                        i <- range 1 i'
                        singleton $ A.fromFoldable $ do
                           j <- range 1 j'
                           singleton (evalFwd (ρ :- x ↦ V.Int β i :- y ↦ V.Int β' j) e1 α' (tss!(i - 1)!(j - 1)))
               in V.Matrix (α ∧ α') (vss × (i' × β) × (j' × β'))
            _ -> error absurd
      _ -> error absurd
evalFwd ρ e α (T.LetRec δ t) =
   case expand e (LetRec (botOf δ) (Hole false)) of
      LetRec δ' e' ->
         let ρ' = closeDefsFwd ρ δ' α δ' in
         evalFwd (ρ <> ρ') e' α t
      _ -> error absurd
evalFwd ρ e α (T.Lambda _ _) =
   case expand e (Lambda (ElimHole false)) of
      Lambda σ -> V.Closure ρ Lin α σ
      _ -> error absurd
evalFwd ρ e α (T.RecordLookup t xs x) =
   case expand e (RecordLookup (Hole false) x) of
      RecordLookup e' _ ->
         case expand (evalFwd ρ e' α t) (V.Record false (xs <#> (_ ↦ V.Hole false))) of
            V.Record _ xvs ->
               assert ((xvs <#> key) == xs) $ successful (find x xvs)
            _ -> error absurd
      _ -> error absurd
evalFwd ρ e α (T.App (t1 × ρ1 × δ × σ) t2 w t3) =
   case expand e (App (Hole false) (Hole false)) of
      App e1 e2 ->
         case expand (evalFwd ρ e1 α t1) (V.Closure (botOf ρ1) (botOf δ) false (ElimHole false)) of
            V.Closure ρ1' δ' β σ' ->
               let v = evalFwd ρ e2 α t2
                   ρ2 = closeDefsFwd ρ1' δ' β δ'
                   ρ3 × e3 × β' = matchFwd v σ' w in
               evalFwd (ρ1' <> ρ2 <> ρ3) (asExpr e3) (β ∧ β') t3
            _ -> error absurd
      _ -> error absurd
evalFwd ρ e α (T.AppPrim (t1 × PrimOp φ × vs) (t2 × v2)) =
   case expand e (App (Hole false) (Hole false)) of
      App e1 e2 ->
         case expand (evalFwd ρ e1 α t1) (V.Primitive (PrimOp φ) (const (V.Hole false) <$> vs)) of
            V.Primitive _ vs' ->
               let v2' = evalFwd ρ e2 α t2
                   vs'' = zip vs' vs <> singleton (v2' × v2) in
               if φ.arity > length vs'' then V.Primitive (PrimOp φ) (fst <$> vs'') else φ.op_fwd vs''
            _ -> error absurd
      _ -> error absurd
evalFwd ρ e α (T.AppConstr (t1 × c × n) t2) =
   case expand e (App (Hole false) (Hole false)) of
      App e1 e2 ->
         case expand (evalFwd ρ e1 α t1) (V.Constr false c (replicate n (V.Hole false))) of
            V.Constr α' _ vs' ->
               let v = evalFwd ρ e2 α t2 in
               V.Constr (α ∧ α') c (vs' <> singleton v)
            _ -> error absurd
      _ -> error absurd
evalFwd ρ e α (T.Let (T.VarDef w t1) t2) =
   case expand e (Let (VarDef (ElimHole false) (Hole false)) (Hole false)) of
      Let (VarDef σ e1) e2 ->
         let v = evalFwd ρ e1 α t1
             ρ' × _ × α' = matchFwd v σ w in
         evalFwd (ρ <> ρ') e2 α' t2
      _ -> error absurd
