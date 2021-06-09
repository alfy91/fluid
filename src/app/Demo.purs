module App.Demo where

import Prelude hiding (absurd)
import Data.Array (unzip, zip)
import Data.Either (Either(..))
import Data.List (singleton)
import Data.Profunctor.Strong ((&&&))
import Data.Traversable (sequence)
import Data.Tuple (uncurry)
import Effect (Effect)
import Effect.Aff (Aff, runAff_)
import Effect.Console (log)
import Partial.Unsafe (unsafePartial)
import App.Renderer (Fig, FigConstructor, drawFigure, energyTableFig, lineChart, matrixFig)
import Bindings (Var, (↦), find, update)
import DesugarFwd (desugarFwd, desugarModuleFwd)
import Eval (eval, eval_module)
import EvalBwd (evalBwd)
import EvalFwd (evalFwd)
import Lattice (𝔹, botOf, neg)
import Module (openWithDefaultImports, openDatasetAs)
import SExpr (Expr(..), Module(..)) as S
import Util (MayFail, type (×), (×), successful)
import Val (Env, Val(..), holeMatrix, insertMatrix)

selectCell :: Int -> Int -> Int -> Int -> Val 𝔹
selectCell i j i' j' = Matrix true (insertMatrix i j (Hole true) (holeMatrix i' j'))

-- Rewrite example of the form (let <defs> in expr) to a "module" and expr, so we can treat defs as part of
-- the environment that we can easily inspect.
splitDefs :: Partial => Env 𝔹 -> S.Expr 𝔹 -> MayFail (Env 𝔹 × S.Expr 𝔹)
splitDefs ρ (S.Let defs s) =
   (desugarModuleFwd (S.Module (singleton (Left defs))) >>= eval_module ρ) <#> (_ × s)

type Example = Env 𝔹 -> S.Expr 𝔹 -> MayFail (Array Fig)
type VarSpec = {
   var :: Var,
   fig :: FigConstructor
}

example_needed :: Array VarSpec -> FigConstructor -> Val 𝔹 -> Example
example_needed x_figs o_fig o' ρ s0 = do
   ρ' × s <- unsafePartial (splitDefs ρ s0)
   e <- desugarFwd s
   let ρρ' = ρ <> ρ'
   t × o <- eval ρρ' e
   let ρρ'' × _ × _ = evalBwd o' t
       xs = _.var <$> x_figs
   vs <- sequence (flip find ρρ' <$> xs)
   vs' <- sequence (flip find ρρ'' <$> xs)
   pure $ [
      o_fig "output" "LightGreen" (o' × o)
   ] <> ((\({var: x, fig} × vs2) -> fig x "Yellow" vs2) <$> zip x_figs (zip vs' vs))

example_neededBy :: Example
example_neededBy ρ s0 = do
   ρ' × s <- unsafePartial (splitDefs ρ s0)
   e <- desugarFwd s
   t × o <- eval (ρ <> ρ') e
   let ω' = selectCell 1 1 3 3
       ρ'' = update (botOf ρ') ("filter" ↦ ω')
       o' = neg (evalFwd (neg (botOf ρ <> ρ'')) (const true <$> e) true t)
   ω <- find "filter" ρ'
   i <- find "image" ρ'
   i' <- find "image" ρ''
   pure [
      matrixFig "output" "Yellow" (o' × o),
      matrixFig "filter" "LightGreen" (ω' × ω),
      matrixFig "input" "Yellow" (i' × i)
   ]

makeFigure :: String -> Example -> String -> Effect Unit
makeFigure file example divId =
   flip runAff_ (burble file)
   case _ of
      Left e -> log ("Open failed: " <> show e)
      Right (ρ × s) -> do
         drawFigure divId (successful (example ρ s))

-- TODO: consolidate with similar test util code; move to Module?
burble :: String -> Aff (Env 𝔹 × S.Expr 𝔹)
burble file = do
   ρ0 × s <- openWithDefaultImports file
   ρ <- openDatasetAs ("example/linking/" <> "renewables") "data"
   pure ((ρ0 <> ρ) × s)

main :: Effect Unit
main = do
   makeFigure "linking/line-chart"
              (example_needed [{ var: "data", fig: energyTableFig } ] lineChart (Hole false)) "table-1"
   makeFigure "slicing/conv-wrap"
              (example_needed [{ var: "filter", fig: matrixFig }, { var: "image", fig: matrixFig } ]
              matrixFig
              (selectCell 2 1 5 5))
              "fig-1"
   makeFigure "slicing/conv-wrap" example_neededBy "fig-2"
   makeFigure "slicing/conv-zero"
              (example_needed [{ var: "filter", fig: matrixFig }, { var: "image", fig: matrixFig } ]
              matrixFig
              (selectCell 2 1 5 5))
              "fig-3"
   makeFigure "slicing/conv-zero" example_neededBy "fig-4"
