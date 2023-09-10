module App.BarChart where

import Prelude hiding (absurd)

import App.Util (class Reflect, Handler, Renderer, Selector, from, get_intOrNumber, record)
import App.Util.Select (constrArg, field, listElement)
import Data.Maybe (Maybe)
import DataType (cBarChart, f_caption, f_data, f_x, f_y)
import Dict (Dict, get)
import Lattice (𝔹, neg)
import Primitive (string)
import Unsafe.Coerce (unsafeCoerce)
import Util (type (×), (!), definitely')
import Val (Val)
import Web.Event.Event (target)
import Web.Event.EventTarget (EventTarget)

newtype BarChart = BarChart { caption :: String × 𝔹, data :: Array BarChartRecord }
newtype BarChartRecord = BarChartRecord { x :: String × 𝔹, y :: Number × 𝔹 }

foreign import drawBarChart :: Renderer BarChart

instance Reflect (Dict (Val Boolean)) BarChartRecord where
   from r = BarChartRecord
      { x: string.match (get f_x r)
      , y: get_intOrNumber f_y r
      }

instance Reflect (Dict (Val Boolean)) BarChart where
   from r = BarChart
      { caption: string.match (get f_caption r)
      , data: record from <$> from (get f_data r)
      }

barChartHandler :: Handler
barChartHandler ev = toggleBar $ unsafeBarIndex $ target ev
   where
   toggleBar :: Int -> Selector Val
   toggleBar i =
      constrArg cBarChart 0
         $ field f_data
         $ listElement i
         $ neg

   -- [Unsafe] Datum associated with bar chart mouse event; 0-based index of selected bar.
   unsafeBarIndex :: Maybe EventTarget -> Int
   unsafeBarIndex tgt_opt =
      let
         tgt = definitely' $ tgt_opt
      in
         (unsafeCoerce tgt).__data__ ! 0
