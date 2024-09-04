module App.View.TableView where

import Prelude

import App.Util (𝕊, SelState, eventData, isInert, isNone, selClassesFor)
import App.Util.Selector (ViewSelSetter, field, listElement)
import App.View.Util (class Drawable, Renderer, selListener, uiHelpers)
import Dict (Dict)
import Effect (Effect)
import Util (Endo)
import Util.Map (filterKeys, get)
import Util.Set (isEmpty)
import Val (BaseVal, Val(..))
import Web.Event.EventTarget (EventListener, eventListener)

newtype TableView = TableView
   { title :: String
   , filter :: Boolean
   -- homogeneous array of records with fields of primitive type
   , table :: Array (Dict (Val (SelState 𝕊))) -- somewhat anomalous, as elsewhere we have Selectables
   }

type TableViewHelpers =
   { rowKey :: String
   , record_isUsed :: Dict (Val (SelState 𝕊)) -> Boolean
   , record_isReactive :: Dict (Val (SelState 𝕊)) -> Boolean
   , cell_selClassesFor :: String -> SelState 𝕊 -> String
   -- values in table cells are not "unpacked" to Selectable but remain as Val
   , val_val :: Val (SelState 𝕊) -> BaseVal (SelState 𝕊)
   , val_selState :: Val (SelState 𝕊) -> SelState 𝕊
   }

foreign import drawTable :: TableViewHelpers -> EventListener -> Renderer TableView

tableViewHelpers :: TableViewHelpers
tableViewHelpers =
   { rowKey
   , record_isUsed
   , record_isReactive
   , cell_selClassesFor
   , val_val: \(Val _ v) -> v
   , val_selState: \(Val α _) -> α
   }
   where
   rowKey :: String
   rowKey = "__n"

   -- Defined for any record type with fields of primitive type
   record_isUsed :: Dict (Val (SelState 𝕊)) -> Boolean
   record_isUsed r =
      not <<< isEmpty $ flip filterKeys r \k ->
         k /= rowKey && not isNone (get k r # \(Val α _) -> α)

   record_isReactive :: Dict (Val (SelState 𝕊)) -> Boolean
   record_isReactive r =
      not <<< isEmpty $ flip filterKeys r \k ->
         k /= rowKey && not isInert (get k r # \(Val α _) -> α)

   --helper for "we want to display this record"

   cell_selClassesFor :: String -> SelState 𝕊 -> String
   cell_selClassesFor colName s
      | colName == rowKey = ""
      | otherwise = selClassesFor s

instance Drawable TableView where
   draw rSpec figVal _ redraw = do
      toggleListener <- filterToggleListener filterToggler
      drawTable tableViewHelpers toggleListener uiHelpers rSpec
         =<< selListener figVal redraw tableViewSelSetter
      where
      tableViewSelSetter :: ViewSelSetter CellIndex
      tableViewSelSetter { __n, colName } = listElement (__n - 1) <<< field colName

      filterToggleListener :: FilterToggler -> Effect EventListener
      filterToggleListener toggler = eventListener (eventData >>> toggler >>> (\_ -> identity) >>> redraw)

-- convert mouse event data (here, always rowKey) to view change
type FilterToggler = String -> Endo TableView

filterToggler :: FilterToggler
filterToggler _ (TableView view) = TableView view { filter = not view.filter }

-- 1-based index of selected record and name of field; see data binding in .js (0th field name is rowKey)
type CellIndex = { __n :: Int, colName :: String }
