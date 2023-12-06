module Test.Util.Suite where

import Prelude

import App.Fig (LinkedInputsFigSpec, LinkedOutputsFigSpec, LinkedInputsFig, linkedInputsResult, linkedOutputsResult, loadLinkedInputsFig, loadLinkedOutputsFig)
import Data.Either (isLeft)
import Data.Newtype (unwrap)
import Data.Profunctor.Strong ((&&&))
import Effect.Aff (Aff)
import Module (File(..), Folder(..), datasetAs, prelude, initialConfig, loadFile, modules)
import Test.Benchmark.Util (BenchRow)
import Test.Util (Selector, checkPretty, test)
import Util (type (+), type (×), (×))
import Val (Val)

-- benchmarks parameterised on number of iterations
type BenchSuite = (Int × Boolean) -> Array (String × Aff BenchRow)

type TestSpec =
   { imports :: Array String
   , file :: String
   , fwd_expect :: String
   }

type TestBwdSpec =
   { imports :: Array String
   , file :: String
   , bwd_expect_file :: String
   , δv :: Selector Val -- relative to bot
   , fwd_expect :: String
   }

type TestWithDatasetSpec =
   { dataset :: String
   , imports :: Array String
   , file :: String
   }

type TestLinkedOutputsSpec =
   { spec :: LinkedOutputsFigSpec
   , δv :: Selector Val + Selector Val
   , v'_expect :: String
   }

type TestLinkedInputsSpec =
   { spec :: LinkedInputsFigSpec
   , δv :: Selector Val + Selector Val
   , v'_expect :: String
   }

suite :: Array TestSpec -> BenchSuite
suite specs (n × is_bench) = specs <#> (_.file &&& asTest)
   where
   asTest :: TestSpec -> Aff BenchRow
   asTest { file, fwd_expect } = do
      gconfig <- prelude >>= initialConfig
      test (File file) gconfig { δv: identity, fwd_expect, bwd_expect: mempty } (n × is_bench)

bwdSuite :: Array TestBwdSpec -> BenchSuite
bwdSuite specs (n × is_bench) = specs <#> ((_.file >>> ("slicing/" <> _)) &&& asTest)
   where
   folder = File "slicing/"

   asTest :: TestBwdSpec -> Aff BenchRow
   asTest { imports, file, bwd_expect_file, δv, fwd_expect } = do
      gconfig <- prelude >>= modules (File <$> imports) >>= initialConfig
      bwd_expect <- loadFile (Folder "fluid/example") (folder <> File bwd_expect_file)
      test (folder <> File file) gconfig { δv, fwd_expect, bwd_expect } (n × is_bench)

withDatasetSuite :: Array TestWithDatasetSpec -> BenchSuite
withDatasetSuite specs (n × is_bench) = specs <#> (_.file &&& asTest)
   where
   asTest :: TestWithDatasetSpec -> Aff BenchRow
   asTest { imports, dataset, file } = do
      gconfig <- prelude >>= modules (File <$> imports) >>= datasetAs (File dataset) "data" >>= initialConfig
      test (File file) gconfig { δv: identity, fwd_expect: mempty, bwd_expect: mempty } (n × is_bench)

linkedOutputsTest :: TestLinkedOutputsSpec -> Aff Unit
linkedOutputsTest { spec, δv, v'_expect } = do
   v1' × v2' × _ <- loadLinkedOutputsFig spec >>= flip linkedOutputsResult δv
   checkPretty "linked output" v'_expect (if isLeft δv then v2' else v1')

linkedOutputsSuite :: Array TestLinkedOutputsSpec -> Array (String × Aff Unit)
linkedOutputsSuite specs = specs <#> (name &&& linkedOutputsTest)
   where
   name spec = "linked-outputs/" <> unwrap spec.spec.file1 <> " <-> " <> unwrap spec.spec.file2

linkedInputsTest :: TestLinkedInputsSpec -> Aff Unit
linkedInputsTest { spec, δv, v'_expect } = do
   v1' × v2' × _ <- loadLinkedInputsFig spec >>= flip linkedInputsResult δv
   checkPretty "linked input" v'_expect (if isLeft δv then v2' else v1')

linkedInputsSuite :: Array TestLinkedInputsSpec -> Array (String × Aff Unit)
linkedInputsSuite specs = specs <#> (name &&& linkedInputsTest)
   where
   name { spec } = "linked-inputs/" <> unwrap spec.file

loadLinkedInputsTest :: TestLinkedInputsSpec -> Aff (LinkedInputsFig × (Selector Val + Selector Val))
loadLinkedInputsTest { spec, δv } = (_ × δv) <$> loadLinkedInputsFig spec
