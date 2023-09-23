module Benchmark.Util where

import Prelude

import Control.Monad.Writer (WriterT, runWriterT)
import Data.Array (intersperse)
import Data.Foldable (fold)
import Data.JSDate (JSDate)
import Data.JSDate (now) as JSDate
import Effect.Class (class MonadEffect, liftEffect)
import Test.Spec.Microtime (microtime)
import Util (type (×), (×))

newtype File = File String
newtype Folder = Folder String

derive newtype instance Show File
derive newtype instance Semigroup File
derive newtype instance Monoid File

data BenchRow = BenchRow TraceRow GraphRow

newtype BenchAcc = BenchAcc (Array (String × BenchRow))

type WithBenchAcc g a = WriterT BenchAcc g a

runWithBenchAcc :: forall g a. Monad g => WithBenchAcc g a -> g (a × BenchAcc)
runWithBenchAcc = runWriterT

derive newtype instance Semigroup BenchAcc
derive newtype instance Monoid BenchAcc

type TraceRow =
   { tEval :: Number
   , tBwd :: Number
   , tFwd :: Number
   }

type GraphRow =
   { tEval :: Number
   , tBwd :: Number
   , tFwd :: Number
   , tFwdDemorgan :: Number
   , tBwdAll :: Number
   }

instance Show BenchAcc where
   show (BenchAcc rows) =
      "Test-Name, Trace-Eval, Trace-Bwd, Trace-Fwd, Graph-Eval, Graph-Bwd, Graph-Fwd, Graph-FwdDeMorgan, Graph-BwdAll\n"
         <> (fold $ intersperse "\n" (map rowShow rows))

rowShow :: String × BenchRow -> String
rowShow (str × row) = str <> "," <> show row

instance Show BenchRow where
   show (BenchRow trRow grRow) = fold $ intersperse ","
      [ show trRow.tEval
      , show trRow.tBwd
      , show trRow.tFwd
      , show grRow.tEval
      , show grRow.tBwd
      , show grRow.tFwd
      , show grRow.tFwdDemorgan
      , show grRow.tBwdAll
      ]

now :: forall m. MonadEffect m => m JSDate
now = liftEffect JSDate.now

tdiff :: Number -> Number -> Number
tdiff x y = sub y x

preciseTime :: forall m. MonadEffect m => m Number
preciseTime = liftEffect microtime