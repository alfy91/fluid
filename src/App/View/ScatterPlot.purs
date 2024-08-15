module App.View.ScatterPlot where

import Prelude

import App.Util (class Reflect, SelState, Selectable, 𝕊, ViewSelector, from, record, isPrimary, isSecondary)
import App.Util.Selector (field, listElement, scatterPlot)
import App.View.LineChart (Point(..))
import App.View.Util (class Drawable, Renderer, selListener, uiHelpers)
import Bind ((↦))
import Data.Int (toNumber)
import DataType (f_caption, f_data, f_xlabel, f_ylabel)
import Dict (Dict)
import Primitive (string, unpack)
import Util.Map (get)
import Val (Val)
import Foreign.Object (Object, fromFoldable)
import Util ((!))
import Data.Tuple (snd)

newtype ScatterPlot = ScatterPlot
   { caption :: Selectable String
   , points :: Array Point
   , xlabel :: Selectable String
   , ylabel :: Selectable String
   }

type ScatterPlotHelpers =
   { point_attrs :: ScatterPlot -> PointIndex -> Object String }

foreign import drawScatterPlot :: ScatterPlotHelpers -> Renderer ScatterPlot Unit -- draws

drawScatterPlot' :: Renderer ScatterPlot Unit
drawScatterPlot' = drawScatterPlot
   { point_attrs }

instance Drawable ScatterPlot Unit where
   draw redraw divId suffix view viewState =
      drawScatterPlot' uiHelpers { divId, suffix, view, viewState } =<< selListener redraw scatterPlotSelector
      where
      scatterPlotSelector :: ViewSelector PointIndex
      scatterPlotSelector { i } = scatterPlot <<< field f_data <<< listElement i

instance Reflect (Dict (Val (SelState 𝕊))) ScatterPlot where
   from r = ScatterPlot
      { caption: unpack string (get f_caption r)
      , points: record from <$> from (get f_data r)
      , xlabel: unpack string (get f_xlabel r)
      , ylabel: unpack string (get f_ylabel r)
      }

type PointIndex = { i :: Int }

point_smallRadius :: Int
point_smallRadius = 2

point_attrs :: ScatterPlot -> PointIndex -> Object String
point_attrs (ScatterPlot { points }) { i } =
   fromFoldable
      [ "r" ↦ show (toNumber point_smallRadius * if isPrimary sel then 1.6 else if isSecondary sel then 1.25 else 1.0) ]
   where
   Point { y } = points ! i
   sel = snd y
