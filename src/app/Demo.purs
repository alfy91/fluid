module App.Demo where

import Prelude hiding (absurd)
import Data.Either (Either(..))
import Data.List (singleton)
import Data.Foldable (length)
import Data.Traversable (sequence, sequence_)
import Data.Tuple (fst)
import Effect (Effect)
import Effect.Aff (Aff, runAff_)
import Effect.Console (log)
import Partial.Unsafe (unsafePartial)
import App.Renderer (Fig, SubFig, drawFig, makeSubFig)
import App.Util (HTMLId)
import Bindings (Bind, Var, find, update)
import DesugarFwd (desugarFwd, desugarModuleFwd)
import Eval (eval, eval_module)
import EvalBwd (evalBwd)
import EvalFwd (evalFwd)
import Expl (Expl)
import Expr (Expr)
import Lattice (𝔹, botOf, neg)
import Module (File(..), open, openDatasetAs)
import Primitive (Slice)
import SExpr (Expr(..), Module(..), RecDefs, VarDefs) as S
import Test.Util (LinkConfig, doLink, selectBarChart_data, selectCell, selectNth, select_y)
import Util (Endo, MayFail, type (×), (×), type (+), successful)
import Util.SnocList (splitAt)
import Val (Env, Val)

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
splitDefs ρ0 s' = unsafePartial $ do
   let defs × s = unpack s'
   ρ0ρ <- desugarModuleFwd (S.Module (singleton defs)) >>= eval_module ρ0
   let _ × ρ = splitAt (length ρ0ρ - length ρ0) ρ0ρ
   pure { ρ, s }
   where unpack :: Partial => S.Expr 𝔹 -> (S.VarDefs 𝔹 + S.RecDefs 𝔹) × S.Expr 𝔹
         unpack (S.LetRec defs s)   = Right defs × s
         unpack (S.Let defs s)      = Left defs × s

varFig :: Partial => Var × Slice (Val 𝔹) -> SubFig
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
   unsafePartial $ pure $ varFig (x × (v' × v))

valFigs :: Val 𝔹 -> NeedsSpec -> Slice (Env 𝔹) -> MayFail (Array SubFig)
valFigs o { vars, o' } (ρ' × ρ) = do
   figs <- sequence (flip varFig' (ρ' × ρ) <$> vars)
   unsafePartial $ pure $
      figs <> [ makeSubFig { title: "output", uv: o' × o } ]

type NeedsSpec = {
   vars  :: Array Var,     -- variables we want subfigs for
   o'    :: Val 𝔹          -- selection on output
}

type NeedsResult = {
   ρ0'   :: Env 𝔹,         -- selection on ambient environment
   ρ'    :: Env 𝔹          -- selection on local environment
}

needs :: Partial => NeedsSpec -> Example -> MayFail (Array SubFig)
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
   makeSubfigs :: Example -> MayFail (Array SubFig)
}

type LinkingFigSpec = {
   divId :: HTMLId,
   config :: LinkConfig
}

-- TODO: not every example should run with this dataset.
fig :: FigSpec -> Aff Fig
fig { divId, file, makeSubfigs } = do
   ρ0 × ρ <- openDatasetAs (File "example/linking/renewables") "data"
   { ρ: ρ1, s: s1 } <- (successful <<< splitDefs (ρ0 <> ρ)) <$> open file
   let subfigs = successful (makeSubfigs { ρ0, ρ: ρ <> ρ1, s: s1 })
   pure { divId, subfigs }

linkingFig :: Partial => LinkingFigSpec -> Aff Fig
linkingFig { divId, config } = do
   link <- doLink config
   pure { divId, subfigs: [
      makeSubFig { title: "primary view", uv: config.v1_sel × link.v1 },
      makeSubFig { title: "linked view", uv: link.v2 },
      makeSubFig { title: "common data", uv: link.data_sel }
   ] }

fig1 :: LinkingFigSpec
fig1 = {
   divId: "fig-1",
   config: {
      file1: File "bar-chart",
      file2: File "line-chart",
      dataFile: File "renewables",
      dataVar: "data",
      v1_sel: selectBarChart_data (selectNth 1 (select_y))
   }
}

figConv1 :: Partial => FigSpec
figConv1 = {
   divId: "fig-conv-1",
   file: File "slicing/conv-emboss",
   makeSubfigs: needs {
      vars: ["image", "filter"],
      o': selectCell 2 2 5 5
   }
}

main :: Effect Unit
main = unsafePartial $
   flip runAff_ (sequence [fig figConv1, linkingFig fig1])
   case _ of
      Left err -> log $ show err
      Right figs ->
         sequence_ $ drawFig <$> figs
