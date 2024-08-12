module App.View.ScatterPlot
   ( PointIndex
   , RScatterPlot(..)
   , RScatterPlotHelpers
   , point_smallRadius
   ) where

import Prelude

import App.Util (class Reflect, ReactState, Relectable, ViewSelector, 𝕊, from, fromℝ, isNone, isPrimary, isSecondary, recordℝ, rupCompare)
import App.Util.Selector (field, listElement, scatterPlot)
import App.View.LineChart (RPoint(..))
import App.View.Util (class Drawable, RRenderer, selListener, uiRHelpers)
import Bind ((↦))
import Data.Int (toNumber)
import Data.Tuple (snd)
import DataType (f_caption, f_data, f_xlabel, f_ylabel)
import Dict (Dict)
import Foreign.Object (Object, fromFoldable)
import Primitive (string, unpack)
import Util ((!))
import Util.Map (get)
import Val (Val)

newtype RScatterPlot = RScatterPlot
   { caption :: Relectable String
   , points :: Array RPoint
   , xlabel :: Relectable String
   , ylabel :: Relectable String
   }

type RScatterPlotHelpers =
   { rpoint_attrs :: RScatterPlot -> PointIndex -> Object String }

foreign import drawRScatterPlot :: RScatterPlotHelpers -> RRenderer RScatterPlot Unit -- draws 

drawRScatterPlot' :: RRenderer RScatterPlot Unit
drawRScatterPlot' = drawRScatterPlot
   { rpoint_attrs }

instance Drawable RScatterPlot Unit where
   draw divId suffix redraw view viewState =
      drawRScatterPlot' { uiRHelpers, divId, suffix, view, viewState } =<< selListener redraw scatterPlotSelector
      where
      scatterPlotSelector :: ViewSelector PointIndex
      scatterPlotSelector { i } = scatterPlot <<< field f_data <<< listElement i

instance Reflect (Dict (Val (ReactState 𝕊))) RScatterPlot where
   from r = RScatterPlot
      { caption: unpack string (get f_caption r)
      , points: recordℝ from <$> from (get f_data r)
      , xlabel: unpack string (get f_xlabel r)
      , ylabel: unpack string (get f_ylabel r)
      }

type PointIndex = { i :: Int }

point_smallRadius :: Int
point_smallRadius = 2

rpoint_attrs :: RScatterPlot -> PointIndex -> Object String
rpoint_attrs (RScatterPlot { points }) { i } =
   fromFoldable
      [ "r" ↦ show (toNumber point_smallRadius * if isPrimary sel then 2.5 else if isSecondary sel then 1.5 else if isNone sel then 0.5 else 1.0) ]
   where
   RPoint { x, y } = points ! i
   sel1 = snd y
   sel2 = snd x
   sel = fromℝ (rupCompare sel1 sel2)

{-}
newtype ScatterPlot = ScatterPlot
   { caption :: Selectable String
   , points :: Array Point
   , xlabel :: Selectable String
   , ylabel :: Selectable String
   }

type ScatterPlotHelpers =
   { point_attrs :: ScatterPlot -> PointIndex -> Object String }

foreign import drawScatterPlot :: ScatterPlotHelpers -> Renderer ScatterPlot Unit -- draws 


instance Drawable ScatterPlot Unit where
   draw divId suffix redraw view viewState =
      drawScatterPlot' { uiHelpers, divId, suffix, view, viewState } =<< selListener redraw scatterPlotSelector
      where
      scatterPlotSelector :: ViewSelector PointIndex
      scatterPlotSelector { i } = scatterPlot <<< field f_data <<< listElement i

drawScatterPlot' :: Renderer ScatterPlot Unit
drawScatterPlot' = drawScatterPlot
   { point_attrs }


instance Reflect (Dict (Val (SelState 𝕊))) ScatterPlot where
   from r = ScatterPlot
      { caption: unpack string (get f_caption r)
      , points: record from <$> from (get f_data r)
      , xlabel: unpack string (get f_xlabel r)
      , ylabel: unpack string (get f_ylabel r)
      }


point_attrs :: ScatterPlot -> PointIndex -> Object String
point_attrs (ScatterPlot { points }) { i } =
   fromFoldable
      [ "r" ↦ show (toNumber point_smallRadius * if isPrimary sel then 2.5 else if isSecondary sel then 1.5 else if isNone sel then 0.5 else 1.0) ]
   where
   Point { x, y } = points ! i
   sel1 = snd y
   sel2 = snd x
   sel = sel1 ∨ sel2
-}