module App.Demo where

import Prelude hiding (absurd)
import Data.Either (Either(..))
import Data.List (singleton)
import Effect (Effect)
import Effect.Aff (runAff_)
import Effect.Console (log)
import Partial.Unsafe (unsafePartial)
import App.Renderer (MatrixFig, drawBarChart, drawFigure, matrixFig)
import Bindings ((↦), find, update)
import DesugarFwd (desugarFwd, desugarModuleFwd)
import Eval (eval, eval_module)
import EvalBwd (evalBwd)
import EvalFwd (evalFwd)
import Lattice (𝔹, botOf, neg)
import Module (openWithDefaultImports)
import SExpr (Expr(..), Module(..)) as S
import Test.Util (desugarEval)
import Util (MayFail, type (×), (×), successful)
import Val (Env, Val(..), holeMatrix, insertMatrix)

selectCell :: Int -> Int -> Int -> Int -> Val 𝔹
selectCell i j i' j' = Matrix true (insertMatrix i j (Hole true) (holeMatrix i' j'))

-- Rewrite example of the form (let <defs> in expr) to a "module" and expr, so we can treat defs as part of
-- the environment that we can easily inspect.
splitDefs :: Partial => Env 𝔹 -> S.Expr 𝔹 -> MayFail (Env 𝔹 × S.Expr 𝔹)
splitDefs ρ (S.Let defs s) =
   (desugarModuleFwd (S.Module (singleton (Left defs))) >>= eval_module ρ) <#> (_ × s)

type ConvExample = Env 𝔹 -> S.Expr 𝔹 -> MayFail (Array MatrixFig)

example_needed :: ConvExample
example_needed ρ s0 = do
   ρ' × s <- unsafePartial (splitDefs ρ s0)
   t × o <- desugarEval (ρ <> ρ') s
   let o' = selectCell 2 1 5 5
       ρρ' × _ × _ = evalBwd o' t
   ω <- find "filter" ρ'
   i <- find "image" ρ'
   ω' <- find "filter" ρρ'
   i' <- find "image" ρρ'
   pure [
      matrixFig "output" "LightGreen" (o' × o),
      matrixFig "filter" "Yellow" (ω' × ω),
      matrixFig "input" "Yellow" (i' × i)
   ]

example_neededBy :: ConvExample
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

makeFigure :: String -> ConvExample -> String -> Effect Unit
makeFigure file example divId =
   flip runAff_ (openWithDefaultImports ("slicing/" <> file))
   case _ of
      Left e -> log ("Open failed: " <> show e)
      Right (ρ × s) -> drawFigure divId (successful (example ρ s))

main :: Effect Unit
main = do
   drawBarChart "fig-bar-chart"
{-
   makeFigure "conv-wrap" example_needed "fig-1"
   makeFigure "conv-wrap" example_neededBy "fig-2"
   makeFigure "conv-zero" example_needed "fig-3"
   makeFigure "conv-zero" example_neededBy "fig-4"
-}
