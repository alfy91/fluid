module Eval where

import Prelude hiding (absurd, apply)
import Data.Array (fromFoldable)
import Data.Bifunctor (bimap)
import Data.Either (Either(..), note)
import Data.List (List(..), (:), length, range, singleton, unzip, snoc)
import Data.Map (lookup)
import Data.Map.Internal (keys)
import Data.Traversable (sequence, traverse)
import Bindings (Bindings(..), (:+:), (↦), find, varAnon)
import DataType (Ctr, arity, checkDataType, cPair, dataTypeForKeys)
import Expl (Expl(..), VarDef(..)) as T
import Expl (Expl, Match(..))
import Expr (Cont(..), Elim(..), Expr(..), Module(..), RecDefs, VarDef(..), asExpr)
import Lattice (𝔹)
import Pretty (pretty, render)
import Primitive (apply, to)
import Util (MayFail, type (×), (×), absurd, check, error, report, successful)
import Val (Env, Val)
import Val (Val(..)) as V

match :: Val 𝔹 -> Elim 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × Match 𝔹)
match _ ElimHole                          = error "todo"
match v (ElimVar x κ)
   | x == varAnon                         = pure $ Empty × κ × MatchVarAnon v
   | otherwise                            = pure ((Empty :+: x ↦ v) × κ × MatchVar x)
match (V.Constr _ c vs) (ElimConstr κs)   = do
   checkDataType "Pattern mismatch: " c κs
   κ <- note ("Incomplete pattern: no branch for " <> show c) (lookup c κs)
   ρ × κ' × ws <- matchArgs c vs κ
   pure (ρ × κ' × MatchConstr c ws)
match v (ElimConstr κs)                   = do
   d <- dataTypeForKeys (keys κs)
   report ("Pattern mismatch: " <> render (pretty v) <> " is not a constructor value, expected " <> show d)

matchArgs :: Ctr -> List (Val 𝔹) -> Cont 𝔹 -> MayFail (Env 𝔹 × Cont 𝔹 × List (Match 𝔹))
matchArgs _ Nil κ                   = pure $ Empty × κ × Nil
matchArgs c (v : vs) (ContElim σ)   = do
   ρ  × κ'  × w  <- match v σ
   ρ' × κ'' × ws <- matchArgs c vs κ'
   pure ((ρ <> ρ') × κ'' × snoc ws w)
matchArgs c (_ : vs) (ContExpr _)   = report $
   show (length vs + 1) <> " extra argument(s) to " <> show c <> "; did you forget parentheses in lambda pattern?"
matchArgs _ _ _ = error absurd

closeDefs :: Env 𝔹 -> RecDefs 𝔹 -> RecDefs 𝔹 -> Env 𝔹
closeDefs _ _ Empty = Empty
closeDefs ρ δ0 (δ :+: f ↦ σ) = closeDefs ρ δ0 δ :+: f ↦ V.Closure ρ δ0 σ

checkArity :: Ctr -> Int -> MayFail Unit
checkArity c n = do
   n' <- arity c
   check (n' >= n) (show c <> " got " <> show n <> " argument(s), expects at most " <> show n')

eval :: Env 𝔹 -> Expr 𝔹 -> MayFail (Expl 𝔹 × Val 𝔹)
eval ρ Hole          = error absurd
eval ρ (Var x)       = (T.Var ρ x × _) <$> find x ρ
eval ρ (Op op)       =  (T.Op ρ op × _) <$> find op ρ
eval ρ (Int _ n)     = pure (T.Int ρ n × V.Int false n)
eval ρ (Float _ n)   = pure (T.Float ρ n × V.Float false n)
eval ρ (Str _ str)   = pure (T.Str ρ str × V.Str false str)
eval ρ (Constr _ c es) = do
   checkArity c (length es)
   ts × vs <- traverse (eval ρ) es <#> unzip
   pure (T.Constr ρ c ts × V.Constr false c vs)
eval ρ (Matrix _ e (x × y) e') = do
   t × v <- eval ρ e'
   case v of
      V.Hole -> error absurd
      V.Constr _ c (v1 : v2 : Nil) | c == cPair -> do
         let i' × j' = to v1 × to v2
         check (i' × j' >= 1 × 1) ("array must be at least (" <> show (1 × 1) <> "); got (" <> show (i' × j') <> ")")
         tss × vss <- unzipToArray <$> ((<$>) unzipToArray) <$> (sequence $ do
            i <- range 1 i'
            singleton $ sequence $ do
               j <- range 1 j'
               singleton (eval ((ρ :+: x ↦ V.Int false i) :+: y ↦ V.Int false j) e))
         pure (T.Matrix tss (x × y) (i' × j') t × V.Matrix false vss (i' × j'))
      v' -> report ("Array dimensions must be pair of ints; got " <> render (pretty v'))
   where
   unzipToArray :: forall a b . List (a × b) -> Array a × Array b
   unzipToArray = unzip >>> bimap fromFoldable fromFoldable
eval ρ (LetRec δ e) = do
   let ρ' = closeDefs ρ δ δ
   t × v <- eval (ρ <> ρ') e
   pure (T.LetRec δ t × v)
eval ρ (Lambda σ) =
   pure (T.Lambda ρ σ × V.Closure ρ Empty σ)
eval ρ (App e e') = do
   t × v <- eval ρ e
   t' × v' <- eval ρ e'
   case v of
      V.Hole -> error absurd
      V.Closure ρ1 δ σ -> do
         let ρ2 = closeDefs ρ1 δ δ
         ρ3 × e'' × w <- match v' σ
         t'' × v'' <- eval (ρ1 <> ρ2 <> ρ3) (asExpr e'')
         pure (T.App (t × ρ1 × δ × σ) t' w t'' × v'')
      V.Primitive _ φ ->
         pure (T.AppPrim (t × φ) (t' × v') × apply φ v')
      V.Constr _ c vs -> do
         check (successful (arity c) > length vs) ("Too many arguments to " <> show c)
         pure (T.AppConstr (t × c × vs) (t' × v') × V.Constr false c (vs <> singleton v'))
      _ -> report "Expected closure, operator or unsaturated constructor"
eval ρ (BinaryApp e op e') = do
   t × v <- eval ρ e
   t' × v' <- eval ρ e'
   v_φ <- find op ρ
   case v_φ of
      V.Hole -> error absurd
      V.Primitive _ φ ->
         case apply φ v of
            V.Hole -> error absurd
            V.Primitive _ φ_v -> pure (T.BinaryApp (t × v) (op × φ) φ_v (t' × v') × apply φ_v v')
            _ -> report "Not a binary operator"
      _ -> report "Not an operator"
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
   eval_module (ρ <> closeDefs ρ δ δ) (Module ds)
