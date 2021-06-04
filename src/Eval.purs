module Eval where

import Prelude hiding (absurd)
import Data.Array (fromFoldable)
import Data.Bifunctor (bimap)
import Data.Either (Either(..), note)
import Data.List (List(..), (:), (\\), length, range, singleton, unzip)
import Data.Map (lookup)
import Data.Map.Internal (keys)
import Data.Newtype (unwrap)
import Data.Profunctor.Strong (second)
import Data.Traversable (sequence, traverse)
import Data.Tuple (curry)
import Bindings (Bindings(..), Var, (:+:), (↦), find, varAnon)
import Bindings2 (Bind(..), asBindings, asBindings2)
import Bindings2 ((↦)) as B
import DataType (Ctr, arity, cPair, dataTypeFor)
import Expl (Expl(..), VarDef(..)) as T
import Expl (Expl, Match(..))
import Expr (Cont(..), Elim(..), Expr(..), Module(..), RecDefs, VarDef(..), asExpr, asElim)
import Lattice (𝔹, checkConsistent)
import Pretty (prettyP)
import Primitive (match) as P
import Util (MayFail, type (×), (×), absurd, check, error, report, successful)
import Util.SnocList (SnocList(..), (:-), zipWith)
import Util.SnocList (unzip) as S
import Val (Env, Env2, PrimOp(..), Val)
import Val (Val(..)) as V

patternMismatch :: String -> String -> String
patternMismatch s s' = "Pattern mismatch: found " <> s <> ", expected " <> s'

match :: Val 𝔹 -> Elim 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × Match 𝔹)
match _ (ElimHole _)                      = error absurd
match v (ElimVar x κ)   | x == varAnon    = pure (Empty × κ × MatchVarAnon v)
                        | otherwise       = pure ((Empty :+: x ↦ v) × κ × MatchVar x)
match (V.Constr _ c vs) (ElimConstr m) = do
   checkConsistent "Pattern mismatch: " c (keys m)
   κ <- note ("Incomplete patterns: no branch for " <> show c) (lookup c m)
   (second (\ws -> MatchConstr c ws (keys m \\ singleton c))) <$> matchArgs c vs κ
match v (ElimConstr m)                    = (report <<< patternMismatch (prettyP v)) =<< show <$> dataTypeFor (keys m)
match (V.Record _ xvs) (ElimRecord xs κ)  = (second (asBindings2 >>> MatchRecord)) <$> (matchRecord (asBindings xvs) xs κ)
match v (ElimRecord xs _)                 = report (patternMismatch (prettyP v) (show xs))

matchArgs :: Ctr -> List (Val 𝔹) -> Cont 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × List (Match 𝔹))
matchArgs _ Nil κ = pure (Empty × κ × Nil)
matchArgs c (v : vs) (ContElim σ) = do
   ρ  × κ'  × w  <- match v σ
   ρ' × κ'' × ws <- matchArgs c vs κ'
   pure ((ρ <> ρ') × κ'' × (w : ws))
matchArgs c (_ : vs) (ContExpr _) = report $
   show (length vs + 1) <> " extra argument(s) to " <> show c <> "; did you forget parentheses in lambda pattern?"
matchArgs _ _ _ = error absurd

matchRecord :: Bindings Val 𝔹 -> SnocList Var -> Cont 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × Bindings Match 𝔹)
matchRecord Empty SnocNil κ               = pure (Empty × κ × Empty)
matchRecord (xvs :+: x ↦ v) (xs :- x') σ  = do
   check (x == x') (patternMismatch (show x) (show x'))
   ρ × σ' × xws <- matchRecord xvs xs σ
   ρ' × κ × w <- match v (asElim σ')
   pure ((ρ <> ρ') × κ × (xws :+: x ↦ w))
matchRecord (_ :+: x ↦ _) SnocNil _       = report (patternMismatch "end of record pattern" (show x))
matchRecord Empty (_ :- x) _              = report (patternMismatch "end of record" (show x))

closeDefs :: Env2 𝔹 -> RecDefs 𝔹 -> RecDefs 𝔹 -> Env2 𝔹
closeDefs _ _ Empty = SnocNil
closeDefs ρ δ0 (δ :+: f ↦ σ) = closeDefs ρ δ0 δ :- Bind (f B.↦ V.Closure ρ (asBindings2 δ0) σ)

checkArity :: Ctr -> Int -> MayFail Unit
checkArity c n = do
   n' <- arity c
   check (n' >= n) (show c <> " got " <> show n <> " argument(s), expects at most " <> show n')

eval :: Env 𝔹 -> Expr 𝔹 -> MayFail (Expl 𝔹 × Val 𝔹)
eval ρ (Hole _)      = error absurd
eval ρ (Var x)       = (T.Var (asBindings2 ρ) x × _) <$> find x ρ
eval ρ (Op op)       = (T.Op (asBindings2 ρ) op × _) <$> find op ρ
eval ρ (Int _ n)     = pure (T.Int (asBindings2 ρ) n × V.Int false n)
eval ρ (Float _ n)   = pure (T.Float (asBindings2 ρ) n × V.Float false n)
eval ρ (Str _ str)   = pure (T.Str (asBindings2 ρ) str × V.Str false str)
eval ρ (Record _ xes) = do
   let xs × es = xes <#> unwrap # S.unzip
   ts × vs <- traverse (eval ρ) es <#> S.unzip
   pure (T.Record (asBindings2 ρ) (zipWith (curry Bind) xs ts) × V.Record false (zipWith (curry Bind) xs vs))
eval ρ (Constr _ c es) = do
   checkArity c (length es)
   ts × vs <- traverse (eval ρ) es <#> unzip
   pure (T.Constr (asBindings2 ρ) c ts × V.Constr false c vs)
eval ρ (Matrix _ e (x × y) e') = do
   t × v <- eval ρ e'
   case v of
      V.Hole _ -> error absurd
      V.Constr _ c (v1 : v2 : Nil) | c == cPair -> do
         let (i' × _) × (j' × _) = P.match v1 × P.match v2
         check (i' × j' >= 1 × 1) ("array must be at least (" <> show (1 × 1) <> "); got (" <> show (i' × j') <> ")")
         tss × vss <- unzipToArray <$> ((<$>) unzipToArray) <$> (sequence $ do
            i <- range 1 i'
            singleton $ sequence $ do
               j <- range 1 j'
               singleton (eval ((ρ :+: x ↦ V.Int false i) :+: y ↦ V.Int false j) e))
         pure (T.Matrix tss (x × y) (i' × j') t × V.Matrix false (vss × (i' × false) × (j' × false)))
      v' -> report ("Array dimensions must be pair of ints; got " <> prettyP v')
   where
   unzipToArray :: forall a b . List (a × b) -> Array a × Array b
   unzipToArray = unzip >>> bimap fromFoldable fromFoldable
eval ρ (LetRec δ e) = do
   let ρ' = closeDefs (asBindings2 ρ) (asBindings δ) (asBindings δ)
   t × v <- eval (ρ <> asBindings ρ') e
   pure (T.LetRec δ t × v)
eval ρ (Lambda σ) =
   pure (T.Lambda (asBindings2 ρ) σ × V.Closure (asBindings2 ρ) SnocNil σ)
eval ρ (App e e') = do
   t × v <- eval ρ e
   t' × v' <- eval ρ e'
   case v of
      V.Hole _ -> error absurd
      V.Closure ρ1 δ σ -> do
         let ρ2 = closeDefs ρ1 (asBindings δ) (asBindings δ)
         ρ3 × e'' × w <- match v' σ
         t'' × v'' <- eval (asBindings ρ1 <> asBindings ρ2 <> ρ3) (asExpr e'')
         pure (T.App (t × ρ1 × δ × σ) t' w t'' × v'')
      V.Primitive (PrimOp φ) vs ->
         let vs' = vs <> singleton v'
             v'' = if φ.arity > length vs' then V.Primitive (PrimOp φ) vs' else φ.op vs' in
         pure (T.AppPrim (t × PrimOp φ × vs) (t' × v') × v'')
      V.Constr _ c vs -> do
         check (successful (arity c) > length vs) ("Too many arguments to " <> show c)
         pure (T.AppConstr (t × c × length vs) t' × V.Constr false c (vs <> singleton v'))
      _ -> report "Expected closure, operator or unsaturated constructor"
eval ρ (Let (VarDef σ e) e') = do
   t × v <- eval ρ e
   ρ' × _ × w <- match v σ -- terminal type of eliminator is unit, represented as hole
   t' × v' <- eval (ρ <> ρ') e'
   pure (T.Let (T.VarDef w t) t' × v')

eval_module :: Env 𝔹 -> Module 𝔹 -> MayFail (Env 𝔹)
eval_module ρ (Module Nil) = pure ρ
eval_module ρ (Module (Left (VarDef σ e) : ds)) = do
   _  × v <- eval ρ e
   ρ' × _ × w  <- match v σ
   eval_module (ρ <> ρ') (Module ds)
eval_module ρ (Module (Right δ : ds)) =
   eval_module (ρ <> asBindings (closeDefs (asBindings2 ρ) (asBindings δ) (asBindings δ))) (Module ds)
