module Bindings where

import Prelude
import Util (Endo, MayFail, type (×), (×), report)

type Var = String

varAnon = "_" :: Var

data Binding t a = Binding Var (t a)
data Bindings t a = Empty | Extend (Bindings t a) (Binding t a)

infix 6 Binding as ↦
infixl 5 Extend as :+:
infixl 5 update as ◃

find :: forall t a . Var -> Bindings t a -> MayFail (t a)
find x Empty  = report $ "variable " <> x <> " not found"
find x (xs :+: x' ↦ v)
   | x == x'   = pure v
   | otherwise = find x xs

foldEnv :: forall t a b . (Binding t a -> Endo b) -> b -> Bindings t a -> b
foldEnv f z (ρ :+: x ↦ v)   = f (x ↦ v) $ foldEnv f z ρ
foldEnv _ z Empty           = z

update :: forall t a . Bindings t a -> Binding t a -> Bindings t a
update Empty _ = Empty
update (xs :+: x ↦ v) (x' ↦ v')
   | x == x'    = xs :+: x' ↦ v'
   | otherwise  = update xs (x' ↦ v') :+: x ↦ v

splitAt :: forall t a . Int -> Bindings t a -> Bindings t a × Bindings t a
splitAt n ρ
  | n <= 0     = ρ × Empty
  | otherwise  = splitAt' n ρ
   where
   splitAt' :: Int -> Bindings t a -> Bindings t a × Bindings t a
   splitAt' _  Empty        = Empty × Empty
   splitAt' 1  (ρ0 :+: xv)  = ρ0 × Extend Empty xv
   splitAt' m  (ρ0 :+: xv)  = ρ' × (ρ'' :+: xv)
      where
      ρ' × ρ'' = splitAt' (m - 1) ρ0

-- ======================
-- boilerplate
-- ======================
derive instance functorBinding :: Functor t => Functor (Binding t)
derive instance functorBindings :: Functor t => Functor (Bindings t)
