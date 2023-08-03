module Benchmark where

import Prelude
import Effect (Effect)
import Effect.Console (logShow)
import Benchotron.Core (Benchmark, benchFn', mkBenchmark)
--import Benchotron.UI.Console (runSuite)
import Control.Monad.Gen.Common (genTuple)
import Data.Foldable (foldl)
import Data.Set (fromFoldable, Set)
import Data.String.Gen (genDigitString)
import Data.Tuple (uncurry, Tuple(..))
import Graph (outStar, outStarOld, Vertex(..), union, emptyG)
import Test.QuickCheck.Arbitrary (arbitrary)
import Test.QuickCheck.Gen (vectorOf)

main :: Effect Unit
main = do
   let
      ids = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]
      graph = foldl (\g α -> union (Vertex (show α)) (fromFoldable $ map (Vertex <<< show) [ α + 1, α + 2 ]) g) emptyG ids
   logShow graph

--runSuite [ benchOutStar ]

preProcessTuple :: Tuple Vertex (Array Vertex) -> Tuple Vertex (Set Vertex)
preProcessTuple (Tuple α αs) = Tuple α (fromFoldable αs)

benchOutStar :: Benchmark
benchOutStar = mkBenchmark
   { slug: "out-star"
   , title: "comparing fold and fromFoldable"
   , sizes: [ 10, 20, 40, 50, 100 ]
   , sizeInterpretation: "Size of graph being created"
   , inputsPerSize: 3
   , gen: \n -> genTuple (Vertex <$> genDigitString) (vectorOf n (Vertex <$> arbitrary))
   , functions:
        [ benchFn' "outStarFold" (uncurry outStarOld) preProcessTuple
        , benchFn' "outStarFromFoldable" (uncurry outStar) preProcessTuple
        ]
   }
