module App.View.TableView
   ( CellIndex
   , FilterToggler
   , RTableView(..)
   , RTableViewHelpers
   , TableView(..)
   , TableViewHelpers
   , TableViewState
   , drawRTable
   , drawRTable'
   , drawTable
   , drawTable'
   , filterToggler
   , record_isUsed
   , rowKey
   ) where

import Prelude

import App.Util (ReactState, SelState, ViewSelector, 𝕊(..), eventData, {-} from, fromℝ, isNone, recordℝ,-} rselClassesFor, selClassesFor, selected)
import App.Util.Selector (field, listElement)
import App.View.Util (class Drawable, Renderer, RRenderer, selListener, uiHelpers, uiRHelpers)
--import Data.Tuple (snd)
import Dict (Dict)
import Effect (Effect)
import Util (Endo, spy)
import Util.Map (filterKeys, get)
import Util.Set (isEmpty)
import Val (BaseVal, Val(..))
import Web.Event.EventTarget (EventListener, eventListener)

newtype TableView = TableView
   { title :: String
   -- homogeneous array of records with fields of primitive type
   , table :: Array (Dict (Val (SelState 𝕊))) -- somewhat anomalous, as elsewhere we have Selectables
   }

newtype RTableView = RTableView
   { title :: String
   -- homogeneous array of records with fields of primitive type
   , table :: Array (Dict (Val (ReactState 𝕊))) -- somewhat anomalous, as elsewhere we have Selectables
   }

type TableViewState =
   { filter :: Boolean
   -- this is where we'd add in UI to make this filter (3x3) or smth.
   }

type TableViewHelpers =
   { rowKey :: String
   , record_isUsed :: Dict (Val (SelState 𝕊)) -> Boolean
   --, record_isUsed :: Boolean -> Dict (Val (SelState 𝕊)) -> Boolean
   --so record_isUsed(True) is a stand in for record_isUsed(inert?) for true/false
   -- and record_isUsed(False) is a stand in for record_isUsed(not_inert) for true/false
   --, record_isInert :: Dict (Val (SelState 𝕊)) -> Boolean
   , cell_selClassesFor :: String -> SelState 𝕊 -> String
   -- values in table cells are not "unpacked" to Selectable but remain as Val
   , val_val :: Val (SelState 𝕊) -> BaseVal (SelState 𝕊)
   , val_selState :: Val (SelState 𝕊) -> SelState 𝕊
   }

type RTableViewHelpers =
   { rowKey :: String
   --, rrecord_isUsed :: Dict (Val (ReactState 𝕊)) -> Boolean
   --, rrecord_isInert :: Dict (Val (ReactState 𝕊)) -> Boolean
   , cell_rselClassesFor :: String -> ReactState 𝕊 -> String
   -- values in table cells are not "unpacked" to Selectable but remain as Val
   , val_rval :: Val (ReactState 𝕊) -> BaseVal (ReactState 𝕊)
   , val_rselState :: Val (ReactState 𝕊) -> ReactState 𝕊
   }

foreign import drawTable :: TableViewHelpers -> EventListener -> Renderer TableView TableViewState

foreign import drawRTable :: RTableViewHelpers -> EventListener -> RRenderer RTableView TableViewState

drawTable' :: EventListener -> Renderer TableView TableViewState
drawTable' = drawTable
   { rowKey
   , record_isUsed
   --, record_isInert
   , cell_selClassesFor
   , val_val: \(Val _ v) -> v
   , val_selState: \(Val α _) -> α
   }

drawRTable' :: EventListener -> RRenderer RTableView TableViewState
drawRTable' = drawRTable
   { rowKey
   --, rrecord_isUsed
   --, record_isInert
   , cell_rselClassesFor
   , val_rval: \(Val _ v) -> v
   , val_rselState: \(Val α _) -> α
   }

instance Drawable TableView TableViewState where
   draw divId suffix redraw view viewState = do
      toggleListener <- filterToggleListener filterToggler
      drawTable' toggleListener { uiHelpers, divId, suffix, view, viewState } =<< selListener redraw tableViewSelector
      where
      tableViewSelector :: ViewSelector CellIndex
      tableViewSelector { __n, colName } = listElement (__n - 1) <<< field colName

      filterToggleListener :: FilterToggler -> Effect EventListener
      filterToggleListener toggler =
         eventListener (eventData >>> toggler >>> (\_ -> spy "TODO" identity) >>> redraw)

instance Drawable RTableView TableViewState where
   draw divId suffix redraw view viewState = do
      toggleListener <- filterToggleListener filterToggler
      drawRTable' toggleListener { uiRHelpers, divId, suffix, view, viewState } =<< selListener redraw tableViewSelector
      where
      tableViewSelector :: ViewSelector CellIndex
      tableViewSelector { __n, colName } = listElement (__n - 1) <<< field colName

      filterToggleListener :: FilterToggler -> Effect EventListener
      filterToggleListener toggler =
         eventListener (eventData >>> toggler >>> (\_ -> spy "TODO" identity) >>> redraw)

-- convert mouse event data (here, always rowKey) to view change
type FilterToggler = String -> Endo TableViewState

filterToggler :: FilterToggler
filterToggler _ vw = vw { filter = not vw.filter }

-- 1-based index of selected record and name of field; see data binding in .js (0th field name is rowKey)
type CellIndex = { __n :: Int, colName :: String }

rowKey :: String
rowKey = "__n"

-- Defined for any record type with fields of primitive type
record_isUsed :: Dict (Val (SelState 𝕊)) -> Boolean
record_isUsed r =
   not <<< isEmpty $ flip filterKeys r \k ->
      k /= rowKey && selected (not <<< (_ == None) <$> (get k r # \(Val α _) -> α))

{-}
-- this is awful, no? It goes "obtain the value r, by mapping through this function ValSelState, then if it's none, map it to the bottom of a lattice? (take true-> false/bottom in this semilattice)
-- mayhaps I should simply aim to rewrite this.
-- so selected takes us from a SelState to a S, basically, being forced to use semilattice
rrecord_isUsed :: Dict (Val (ReactState 𝕊)) -> Boolean
rrecord_isUsed r =
   not <<< isEmpty $ flip filterKeys r \k ->
      k /= rowKey && ((selected (fromℝ <$> (get k r # \(Val α _) -> α))) == (selState None None))
-}
--make selected relected? or is this more of an issue?
{-}
rrecord_isUsed :: Dict (Val (ReactState 𝕊)) -> Boolean
rrecord_isUsed r =
   not <<< isEmpty $ flip filterKeys r \k ->
      k /= rowKey && selected (not <<< ((fromℝ <$> _) == (Reactive _)) (fromℝ <$> <$> (get k r # \(Val α _) -> α))
-}

-- may be handy as a helper method, but also as a SelState S needs to adapt to ReactState

cell_selClassesFor :: String -> SelState 𝕊 -> String
cell_selClassesFor colName s
   | colName == rowKey = ""
   | otherwise = selClassesFor s

cell_rselClassesFor :: String -> ReactState 𝕊 -> String
cell_rselClassesFor colName s
   | colName == rowKey = ""
   | otherwise = rselClassesFor s
