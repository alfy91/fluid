module App.Renderer where

import Prelude hiding (absurd)
import Data.Array (range, zip)
import Data.Either (Either(..))
import Data.Foldable (length)
import Data.Traversable (sequence, sequence_)
import Data.List (List(..), (:), singleton)
import Data.Tuple (fst, uncurry)
import Effect (Effect)
import Effect.Aff (Aff)
import Partial.Unsafe (unsafePartial)
import Web.Event.EventTarget (eventListener)
import App.BarChart (BarChart, barChartHandler, drawBarChart)
import App.LineChart (LineChart, drawLineChart, lineChartHandler)
import App.MatrixView (MatrixView(..), drawMatrix, matrixViewHandler, matrixRep)
import App.TableView (EnergyTable(..), drawTable, energyRecord)
import App.Util (HTMLId, from, record)
import Bindings (Bind, Var, find, update)
import DataType (cBarChart, cCons, cLineChart, cNil)
import DesugarFwd (desugarFwd, desugarModuleFwd)
import Expl (Expl)
import Expr (Expr)
import Eval (eval, eval_module)
import EvalBwd (evalBwd)
import EvalFwd (evalFwd)
import Lattice (𝔹, botOf, expand, neg)
import Module (File(..), open, openDatasetAs)
import Primitive (Slice, match, match_fwd)
import SExpr (Expr(..), Module(..), RecDefs, VarDefs) as S
import Test.Util (LinkConfig, doLink)
import Util (Endo, MayFail, type (×), type (+), (×), absurd, error, successful)
import Util.SnocList (splitAt)
import Val (Env, Val)
import Val (Val(..)) as V

type Fig = {
   divId :: HTMLId,
   subfigs :: Array SubFig
}

drawFig :: (Unit -> Effect Unit) -> Fig -> Effect Unit
drawFig redraw { divId, subfigs } =
   sequence_ $ uncurry (drawSubFig divId redraw) <$> zip (range 0 (length subfigs - 1)) subfigs

data SubFig =
   MatrixFig MatrixView |
   EnergyTableView EnergyTable |
   LineChartFig LineChart |
   BarChartFig BarChart

drawSubFig :: HTMLId -> (Unit -> Effect Unit) -> Int -> SubFig -> Effect Unit
drawSubFig divId redraw n (MatrixFig fig') = drawMatrix divId n fig' =<< eventListener (matrixViewHandler redraw)
drawSubFig divId _ _ (EnergyTableView fig') = drawTable divId fig'
drawSubFig divId _ _ (LineChartFig fig') = drawLineChart divId fig' =<< eventListener lineChartHandler
drawSubFig divId _ _ (BarChartFig fig') = drawBarChart divId fig' =<< eventListener barChartHandler

-- Convert sliced value to appropriate SubFig, discarding top-level annotations for now.
-- 'from' is partial but encapsulate that here.
makeSubFig :: { title :: String, uv :: Slice (Val 𝔹) } -> SubFig
makeSubFig { title, uv: u × V.Constr _ c (v1 : Nil) } | c == cBarChart =
   case expand u (V.Constr false cBarChart (V.Hole false : Nil)) of
      V.Constr _ _ (u1 : Nil) -> BarChartFig (unsafePartial $ record from (u1 × v1))
      _ -> error absurd
makeSubFig { title, uv: u × V.Constr _ c (v1 : Nil) } | c == cLineChart =
   case expand u (V.Constr false cLineChart (V.Hole false : Nil)) of
      V.Constr _ _ (u1 : Nil) -> LineChartFig (unsafePartial $ record from (u1 × v1))
      _ -> error absurd
makeSubFig { title, uv: u × v@(V.Constr _ c _) } | c == cNil || c == cCons =
   EnergyTableView (EnergyTable { title, table: unsafePartial $ record energyRecord <$> from (u × v) })
makeSubFig { title, uv: u × v@(V.Matrix _ _) } =
   let vss2 = fst (match_fwd (u × v)) × fst (match v) in
   MatrixFig (MatrixView { title, matrix: matrixRep vss2 } )
makeSubFig _ = error absurd

type Example = {
   ρ0 :: Env 𝔹,     -- ambient env (default imports)
   ρ :: Env 𝔹,      -- local env (loaded dataset, if any, plus additional let bindings at beginning of ex)
   s :: S.Expr 𝔹    -- body of example
}

-- Example assumed to be of the form (let <defs> in expr).
type View = {
   ρ :: Env 𝔹,      -- local env (additional let bindings at beginning of ex)
   s :: S.Expr 𝔹    -- body of example
}

-- Interpret a program as a "view" in the sense above. TODO: generalise to sequence of let/let recs, rather than one.
splitDefs :: Env 𝔹 -> S.Expr 𝔹 -> MayFail View
splitDefs ρ0 s' = do
   let defs × s = unsafePartial $ unpack s'
   ρ0ρ <- desugarModuleFwd (S.Module (singleton defs)) >>= eval_module ρ0
   let _ × ρ = splitAt (length ρ0ρ - length ρ0) ρ0ρ
   pure { ρ, s }
   where unpack :: Partial => S.Expr 𝔹 -> (S.VarDefs 𝔹 + S.RecDefs 𝔹) × S.Expr 𝔹
         unpack (S.LetRec defs s)   = Right defs × s
         unpack (S.Let defs s)      = Left defs × s

varFig :: Var × Slice (Val 𝔹) -> SubFig
varFig (x × uv) = makeSubFig { title: x, uv }

type ExampleEval = {
   e     :: Expr 𝔹,
   ρ0ρ   :: Env 𝔹,
   t     :: Expl 𝔹,
   o     :: Val 𝔹
}

evalExample :: Example -> MayFail ExampleEval
evalExample { ρ0, ρ, s } = do
   e <- desugarFwd s
   let ρ0ρ = ρ0 <> ρ
   t × o <- eval ρ0ρ e
   pure { e, ρ0ρ, t, o }

varFig' :: Var -> Slice (Env 𝔹) -> MayFail SubFig
varFig' x (ρ' × ρ) = do
   v <- find x ρ
   v' <- find x ρ'
   pure $ varFig (x × (v' × v))

valFigs :: Val 𝔹 -> NeedsSpec -> Slice (Env 𝔹) -> MayFail (Array SubFig)
valFigs o { vars, o' } (ρ' × ρ) = do
   figs <- sequence (flip varFig' (ρ' × ρ) <$> vars)
   pure $ figs <> [ makeSubFig { title: "output", uv: o' × o } ]

type NeedsSpec = {
   vars  :: Array Var,     -- variables we want subfigs for
   o'    :: Val 𝔹          -- selection on output
}

needs :: NeedsSpec -> Example -> MayFail (Array SubFig)
needs spec { ρ0, ρ, s } = do
   { e, o, t, ρ0ρ } <- evalExample { ρ0, ρ, s }
   let ρ0ρ' × e × α = evalBwd spec.o' t
       ρ0' × ρ' = splitAt (length ρ) ρ0ρ'
       o'' = evalFwd ρ0ρ' e α t
   figs <- valFigs o spec (ρ0ρ' × ρ0ρ)
   pure $ figs <> [ makeSubFig { title: "output", uv: o'' × o } ]

type NeededBySpec = {
   vars     :: Array Var,    -- variables we want subfigs for
   ρ'       :: Env 𝔹         -- selection on local env
}

neededBy :: NeededBySpec -> Example -> MayFail (Unit × Array SubFig)
neededBy { vars, ρ' } { ρ0, ρ, s } = do
   { e, o, t, ρ0ρ } <- evalExample { ρ0, ρ, s }
   let o' = neg (evalFwd (neg (botOf ρ0 <> ρ')) (const true <$> e) true t)
       ρ0'ρ'' = neg (fst (fst (evalBwd (neg o') t)))
       ρ0' × ρ'' = splitAt (length ρ) ρ0'ρ''
   figs <- valFigs o { vars, o' } (ρ' × ρ)
   figs' <- sequence (flip varFig' (ρ'' × ρ) <$> vars)
   pure $ unit × (figs <> figs')

selectOnly :: Bind (Val 𝔹) -> Endo (Env 𝔹)
selectOnly xv ρ = update (botOf ρ) xv

type FigSpec = {
   divId :: HTMLId,
   file :: File,
   needsSpec :: NeedsSpec
}

type LinkingFigSpec = {
   divId :: HTMLId,
   config :: LinkConfig
}

-- TODO: not every example should run with this dataset.
fig :: FigSpec -> Aff Fig
fig { divId, file, needsSpec } = do
   ρ0 × ρ <- openDatasetAs (File "example/linking/renewables") "data"
   { ρ: ρ1, s: s1 } <- (successful <<< splitDefs (ρ0 <> ρ)) <$> open file
   let subfigs = successful (needs needsSpec { ρ0, ρ: ρ <> ρ1, s: s1 })
   pure { divId, subfigs }

linkingFig :: LinkingFigSpec -> Aff Fig
linkingFig { divId, config } = do
   link <- doLink config
   pure { divId, subfigs: [
      makeSubFig { title: "primary view", uv: config.v1_sel × link.v1 },
      makeSubFig { title: "linked view", uv: link.v2 },
      makeSubFig { title: "common data", uv: link.data_sel }
   ] }
