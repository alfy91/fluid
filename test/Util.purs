module Test.Util where

import Prelude hiding (absurd)
import Data.Bitraversable (bitraverse)
import Data.List (elem)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (uncurry)
import Effect (Effect)
import Effect.Aff (Aff)
import Test.Spec (SpecT, before, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Mocha (runMocha)
import DataType (dataTypeFor, typeName)
import DesugarBwd (desugarBwd)
import DesugarFwd (desugarFwd)
import Eval (eval)
import EvalBwd (evalBwd)
import EvalFwd (evalFwd)
import Expl (Expl)
import Expr (Expr(..)) as E
import SExpr (Expr) as S
import Lattice (𝔹, botOf, neg)
import Module (loadFile, openDatasetAs, openWithDefaultImports)
import Pretty (class Pretty, prettyP)
import Util (MayFail, type (×), (×), successful)
import Util.SnocList (splitAt)
import Val (Env, Val(..))

-- Don't enforce expected values for graphics tests (values too complex).
isGraphical :: forall a . Val a -> Boolean
isGraphical (Hole _)       = false
isGraphical (Constr _ c _) = typeName (successful (dataTypeFor c)) `elem` ["GraphicsElement", "Plot"]
isGraphical _              = false

type Test a = SpecT Aff Unit Effect a

run :: forall a . Test a → Effect Unit
run = runMocha -- no reason at all to see the word "Mocha"

desugarEval :: Env 𝔹 -> S.Expr 𝔹 -> MayFail (Expl 𝔹 × Val 𝔹)
desugarEval ρ s = desugarFwd s >>= eval ρ

desugarEval_bwd :: Expl 𝔹 × S.Expr 𝔹 -> Val 𝔹 -> Env 𝔹 × S.Expr 𝔹
desugarEval_bwd (t × s) v = let ρ × e × _ = evalBwd v t in ρ × desugarBwd e s

desugarEval_fwd :: Env 𝔹 -> S.Expr 𝔹 -> Expl 𝔹 -> Val 𝔹
desugarEval_fwd ρ s =
   let _ = evalFwd (botOf ρ) (E.Hole false) false in -- sanity-check that this is defined
   evalFwd ρ (successful (desugarFwd s)) true

checkPretty :: forall a . Pretty a => a -> String -> Aff Unit
checkPretty x expected = prettyP x `shouldEqual` expected

-- v_opt is output slice; v_expect is expected result after round-trip
testWithSetup :: String -> String -> Maybe (Val 𝔹) -> Aff (Env 𝔹 × S.Expr 𝔹) -> Test Unit
testWithSetup name expected v_opt setup =
   before setup $
      it name \(ρ × s) -> do
         let t × v = successful (desugarEval ρ s)
             ρ' × s' = desugarEval_bwd (t × s) (fromMaybe v v_opt)
             v = desugarEval_fwd ρ' s' t
         unless (isGraphical v) (checkPretty v expected)
         case v_opt of
            Nothing -> pure unit
            Just _ -> loadFile "fluid/example" (name <> ".expect") >>= checkPretty s'

test :: String -> String -> Test Unit
test file expected = testWithSetup file expected Nothing (openWithDefaultImports file)

testBwd :: String -> Val 𝔹 -> String -> Test Unit
testBwd file v expected =
   let name = "slicing/" <> file in
   testWithSetup name expected (Just v) (openWithDefaultImports name)

testLink :: String -> Val 𝔹 -> String -> Test Unit
testLink file v1_sel v2_expect =
   let name = "linking/" <> file
       setup = do
         -- the views share an ambient environment ρ0 as well as dataset
         ρ0 × s1 <- openWithDefaultImports (name <> "-1")
         _ × s2 <- openWithDefaultImports (name <> "-2")
         ρ <- openDatasetAs ("example/" <> name <> "-data") "data"
         pure (ρ0 × ρ × s1 × s2) in
   before setup $
      it name \(ρ0 × ρ × s1 × s2) -> do
         let e1 = successful (desugarFwd s1)
             e2 = successful (desugarFwd s2)
             t1 × v1 = successful (eval (ρ0 <> ρ) e1)
             t2 × v2 = successful (eval (ρ0 <> ρ) e2)
             ρ0ρ × _ × _ = evalBwd v1_sel t1
             _ × ρ' = splitAt 1 ρ0ρ
             -- make ρ0 and e2 fully available; ρ0 is too big to operate on, so we use (topOf ρ0)
             -- combine with the negation of the dataset environment slice
             v2' = neg (evalFwd (neg (botOf ρ0 <> ρ')) (const true <$> e2) true t2)
         checkPretty v2' v2_expect

testWithDataset :: String -> String -> Test Unit
testWithDataset dataset file =
   testWithSetup file "" Nothing $
      bitraverse (uncurry openDatasetAs) openWithDefaultImports (("dataset/" <> dataset) × "data" × file) <#>
      (\(ρ × (ρ' × e)) -> (ρ <> ρ') × e)
