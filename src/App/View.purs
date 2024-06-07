module App.View where

import Prelude hiding (absurd)

import App.Util (SelState, Selector, ViewSelector, 𝕊, eventData, from, record, selClass, selClasses)
import App.Util.Selector (multiPlotEntry)
import App.View.BarChart (BarChart) as View
import App.View.BarChart (barChartSelector, bar_fill, bar_stroke, drawBarChart)
import App.View.LineChart (LineChart) as View
import App.View.LineChart (drawLineChart, lineChartSelector, point_radius, point_smallRadius, point_stroke)
import App.View.MatrixView (MatrixView(..)) as View
import App.View.MatrixView (drawMatrix, matrixRep, matrixViewSelector)
import App.View.ScatterPlot (ScatterPlot) as View
import App.View.ScatterPlot (drawScatterPlot, scatterPlotSelector)
import App.View.TableView (TableView(..)) as View
import App.View.TableView (cell_selClass, drawTable, record_isUsed, rowKey, tableViewSelector)
import App.View.Util (HTMLId, UIHelpers)
import Data.Foldable (sequence_)
import Data.List (List(..), (:))
import Data.Tuple (fst, snd, uncurry)
import DataType (cBarChart, cCons, cLineChart, cMultiPlot, cNil, cScatterPlot)
import Dict (Dict)
import Effect (Effect)
import Lattice ((∨))
import Util.Map (mapWithKey)
import Val (BaseVal(..), Val(..))
import Web.Event.EventTarget (EventListener, eventListener)

data View
   -- one for each constructor of the Fluid 'Plot' data type
   = BarChart View.BarChart
   | LineChart View.LineChart
   | ScatterPlot View.ScatterPlot
   | MultiView (Dict View)
   -- plus default visualisations for specific kinds of value
   | MatrixView View.MatrixView
   | TableView View.TableView

drawView :: HTMLId -> String -> (Selector Val -> Effect Unit) -> View -> Effect Unit
drawView divId suffix redraw = case _ of
   MatrixView vw -> drawMatrix { uiHelpers, divId, suffix, view: vw } =<< listener matrixViewSelector
   TableView vw -> drawTable { uiHelpers, divId, suffix, view: vw } =<< listener tableViewSelector
   LineChart vw -> drawLineChart { uiHelpers, divId, suffix, view: vw } =<< listener lineChartSelector
   BarChart vw -> drawBarChart { uiHelpers, divId, suffix, view: vw } =<< listener barChartSelector
   ScatterPlot vw -> drawScatterPlot { uiHelpers, divId, suffix, view: vw } =<< listener scatterPlotSelector
   MultiView vws -> sequence_ $ mapWithKey (\x -> drawView divId x (multiPlotEntry x >>> redraw)) vws
   where
   listener :: forall a. ViewSelector a -> Effect EventListener
   listener selector = eventListener (eventData >>> uncurry selector >>> redraw)

-- Convert annotated value to appropriate View, discarding top-level annotations for now.
view :: Partial => String -> Val (SelState 𝕊) -> View
view _ (Val _ (Constr c (u : Nil))) | c == cBarChart =
   BarChart (record from u)
view _ (Val _ (Constr c (u : Nil))) | c == cLineChart =
   LineChart (record from u)
view title (Val _ (Constr c (u : Nil))) | c == cMultiPlot =
   MultiView (view title <$> from u)
view _ (Val _ (Constr c (u : Nil))) | c == cScatterPlot =
   ScatterPlot (record from u)
view title u@(Val _ (Constr c _)) | c == cNil || c == cCons =
   TableView (View.TableView { title, filter: true, table: record identity <$> from u })
view title (Val _ (Matrix r)) =
   MatrixView (View.MatrixView { title, matrix: matrixRep r })

uiHelpers :: UIHelpers
uiHelpers =
   { val: fst
   , selState: snd
   , join: (∨)
   , selClasses
   , selClass
   , barChart:
        { bar_fill
        , bar_stroke
        }
   , lineChart:
        { point_smallRadius
        , point_radius
        , point_stroke
        }
   , tableView:
        { rowKey
        , record_isUsed
        , cell_selClass
        , val_val: \(Val _ v) -> v
        , val_selState: \(Val α _) -> α
        }
   }
