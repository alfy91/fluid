module App.Demo where

import Prelude hiding (absurd)
import Data.Array (zip)
import Data.Either (Either(..))
import Data.List (List(..), (:), singleton)
import Data.Traversable (sequence, sequence_)
import Effect (Effect)
import Effect.Aff (runAff_)
import Effect.Console (log)
import Partial.Unsafe (unsafePartial)
import App.Renderer (Fig, MakeFig, drawFigure, makeBarChart, makeEnergyTable, matrixFig)
import Bindings (Bind, Var, (↦), find, update)
import DataType (cBarChart, cCons)
import DesugarFwd (desugarFwd, desugarModuleFwd)
import Eval (eval, eval_module)
import EvalBwd (evalBwd)
import EvalFwd (evalFwd)
import Lattice (𝔹, botOf, neg)
import Primitive (Slice)
import SExpr (Expr(..), Module(..), RecDefs, VarDefs) as S
import Test.Util (openFileWithDataset)
import Util (Endo, MayFail, type (×), (×), type (+), successful)
import Util.SnocList (SnocList(..), (:-))
import Val (Env, Val(..), holeMatrix, insertMatrix)

selectCell :: Int -> Int -> Int -> Int -> Val 𝔹
selectCell i j i' j' = Matrix false (insertMatrix i j (Hole true) (holeMatrix i' j'))

selectNth :: Int -> Val 𝔹 -> Val 𝔹
selectNth 0 v = Constr false cCons (v : Hole false : Nil)
selectNth n v = Constr false cCons (Hole false : selectNth (n - 1) v : Nil)

select_y :: Val 𝔹
select_y = Record false (Lin :- "x" ↦ Hole false :- "y" ↦ Hole true)

select_barChart_data :: Val 𝔹 -> Val 𝔹
select_barChart_data v = Constr false cBarChart (Record false (Lin :- "caption" ↦ Hole false :- "data" ↦ v) : Nil)

-- Example assumed to be of the form (let <defs> in expr), so we can treat defs as part of the environment that
-- we can easily inspect.
type Example = {
   ρ0 :: Env 𝔹,     -- ambient environment, including any dataset loaded
   ρ :: Env 𝔹,      -- "local" env (additional bindings introduce by "let" at beginning of ex)
   s :: S.Expr 𝔹    -- body of let
}

type VarSpec = {
   var :: Var,
   fig :: MakeFig
}

type NeededExample = {
   ex       :: Example,
   x_figs   :: Array VarSpec,    -- one for each variable we want a figure for
   o_fig    :: MakeFig,          -- for output
   o'       :: Val 𝔹             -- selection on output
}

type NeededByExample = {
   ex       :: Example,
   x_figs   :: Array VarSpec,    -- one for each variable we want a figure for
   o_fig    :: MakeFig,          -- for output
   ρ'       :: Env 𝔹             -- selection on local env
}

-- Extract the ρ' and s components of an example s'.
splitDefs :: Partial => Env 𝔹 -> S.Expr 𝔹 -> MayFail Example
splitDefs ρ0 s' = do
   let defs × s = unpack s'
   ρ <- desugarModuleFwd (S.Module (singleton defs)) >>= eval_module ρ0
   pure { ρ0, ρ, s }
   where unpack :: S.Expr 𝔹 -> (S.VarDefs 𝔹 + S.RecDefs 𝔹) × S.Expr 𝔹
         unpack (S.LetRec defs s)   = Right defs × s
         unpack (S.Let defs s)      = Left defs × s

varFig :: Partial => VarSpec × Slice (Val 𝔹) -> Fig
varFig ({var: x, fig} × uv) = fig { title: x, uv }

needed :: Partial => NeededExample -> MayFail (Array Fig)
needed { ex: { ρ0, ρ, s }, x_figs, o_fig, o' } = do
   e <- desugarFwd s
   let ρ0ρ = ρ0 <> ρ
   t × o <- eval ρ0ρ e
   let ρ0ρ' × _ × _ = evalBwd o' t
       xs = _.var <$> x_figs
   vs <- sequence (flip find ρ0ρ <$> xs)
   vs' <- sequence (flip find ρ0ρ' <$> xs)
   pure $ [ o_fig { title: "output", uv: o' × o } ] <> (varFig <$> zip x_figs (zip vs' vs))

neededBy :: Partial => NeededByExample -> MayFail (Array Fig)
neededBy { ex: { ρ0, ρ, s }, x_figs, o_fig, ρ' } = do
   e <- desugarFwd s
   let ρ0ρ = ρ0 <> ρ
   t × o <- eval ρ0ρ e
   let o' = neg (evalFwd (neg (botOf ρ0 <> ρ')) (const true <$> e) true t)
       xs = _.var <$> x_figs
   vs <- sequence (flip find ρ <$> xs)
   vs' <- sequence (flip find ρ' <$> xs)
   pure $ [ o_fig { title: "output", uv: o' × o } ] <> (varFig <$> zip x_figs (zip vs' vs))

selectOnly :: Bind (Val 𝔹) -> Endo (Env 𝔹)
selectOnly xv ρ = update (botOf ρ) xv

makeFigures :: Partial => Array String -> (Example -> MayFail (Array Fig)) -> String -> Effect Unit
makeFigures files makeFigs divId =
   flip runAff_ (sequence (openFileWithDataset "example/linking/renewables" <$> files))
   case _ of
      Left e -> log ("Open failed: " <> show e)
      Right ρs -> sequence_ $
         ρs <#> \(ρ × s) -> drawFigure divId (successful (splitDefs ρ s >>= makeFigs))

-- TODO: not every example should run in context of renewables data.
convolutionFigs :: Partial => Effect Unit
convolutionFigs = do
   let x_figs = [{ var: "filter", fig: matrixFig }, { var: "image", fig: matrixFig }] :: Array VarSpec
   makeFigures ["slicing/conv-wrap"]
               (\ex -> needed { ex, x_figs, o_fig: matrixFig, o': selectCell 2 1 5 5 })
               "fig-1"
   makeFigures ["slicing/conv-wrap"]
               (\ex -> neededBy { ex, x_figs, o_fig: matrixFig, ρ': selectOnly ("filter" ↦ selectCell 1 1 3 3) ex.ρ })
               "fig-2"
   makeFigures ["slicing/conv-zero"]
               (\ex -> needed { ex, x_figs, o_fig: matrixFig, o': selectCell 2 1 5 5 })
               "fig-3"
   makeFigures ["slicing/conv-zero"]
               (\ex -> neededBy { ex, x_figs, o_fig: matrixFig, ρ': selectOnly ("filter" ↦ selectCell 1 1 3 3) ex.ρ })
               "fig-4"

linkingFigs :: Partial => Effect Unit
linkingFigs = do
   let x_figs = [{ var: "data", fig: makeEnergyTable }] :: Array VarSpec
   makeFigures ["linking/bar-chart"]
               (\ex -> needed { ex, x_figs, o_fig: makeBarChart, o': select_barChart_data (selectNth 1 (select_y)) })
               "table-1"
   makeFigures ["linking/bar-chart"]
               (\ex -> needed { ex, x_figs, o_fig: makeBarChart, o': select_barChart_data (selectNth 0 (select_y)) })
               "table-2"

main :: Effect Unit
main = unsafePartial $ do
   linkingFigs
   convolutionFigs
