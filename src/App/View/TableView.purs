module App.View.TableView where

import Prelude

import App.Util (SelState, 𝕊(..), classes, getPersistent, getTransient, isInert, isTransient, selClassesFor)
import App.Util.Selector (ViewSelSetter, field, listElement)
import App.View.Util (class Drawable, class Drawable2, draw', selListener, uiHelpers)
import App.View.Util.D3 (ElementType(..), create, datum, setData, setStyles, setText)
import App.View.Util.D3 as D3
import Bind ((↦))
import Data.Array (filter, head, length, null, sort)
import Data.FoldableWithIndex (forWithIndex_)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Number (log)
import Data.Number.Format (fixed, toStringWith)
import Data.Set (toUnfoldable)
import Data.Traversable (for_)
import Dict (Dict)
import Effect (Effect)
import Util (Endo, definitely', error, (!))
import Util.Map (get, keys)
import Val (Array2, BaseVal(..), Val(..))
import Web.Event.EventTarget (EventListener)

type RecordRow = Array (Val (SelState 𝕊)) -- somewhat anomalous, as elsewhere we have Selectables

data Filter = Everything | Interactive | Relevant

newtype TableView = TableView
   { title :: String
   , filter :: Filter
   , colNames :: Array String
   -- homogeneous array of records with fields of primitive type; each row has same length as colNames
   , rows :: Array RecordRow
   }

-- helper functions used by View.purs to decompose array of records (Dict (Val (SelState 𝕊))) into colNames and table
headers :: Array (Dict (Val (SelState 𝕊))) -> Array String
headers records = sort <<< toUnfoldable <<< keys <<< definitely' $ head records

arrayDictToArray2 :: forall a. Array String -> Array (Dict a) -> Array2 a
arrayDictToArray2 = map <<< flip (map <<< flip get)

foreign import createRootElement :: TableView -> TableViewHelpers -> D3.Selection -> String -> Effect D3.Selection
foreign import setSelState :: TableView -> TableViewHelpers -> EventListener -> D3.Selection -> Effect Unit

newtype TableViewHelpers = TableViewHelpers
   { rowKey :: String
   , record_isDisplayable :: Array (Val (SelState 𝕊)) -> Boolean
   , cell_selClassesFor :: String -> SelState 𝕊 -> String
   -- values in rows cells are not "unpacked" to Selecrows but remain as Val
   , val_val :: Val (SelState 𝕊) -> BaseVal (SelState 𝕊)
   , val_selState :: Val (SelState 𝕊) -> SelState 𝕊
   , hasRightBorder :: Array RecordRow -> Int -> Int -> Boolean
   , hasBottomBorder :: Array RecordRow -> Int -> Int -> Boolean
   }

defaultFilter :: Filter
defaultFilter = Interactive

rowKey :: String
rowKey = "__n"

tableViewHelpers :: TableViewHelpers
tableViewHelpers =
   TableViewHelpers
      { rowKey
      , record_isDisplayable
      , cell_selClassesFor
      , val_val
      , val_selState
      , hasRightBorder
      , hasBottomBorder
      }
   where
   val_val (Val _ v) = v
   val_selState (Val α _) = α

   width :: Array RecordRow -> Int
   width rows = length <<< definitely' $ head rows

   record_isDisplayable :: Array (Val (SelState 𝕊)) -> Boolean
   record_isDisplayable r =
      not <<< null $ flip filter r \(Val α _) -> display defaultFilter α
      where
      display :: Filter -> SelState 𝕊 -> Boolean
      display Everything = const true
      display Interactive = not isInert
      display Relevant = not (isNone || isInert)

      isNone :: SelState 𝕊 -> Boolean
      isNone a = getPersistent a == None && getTransient a == None

   cell_selClassesFor :: String -> SelState 𝕊 -> String
   cell_selClassesFor colName s
      | colName == rowKey = ""
      | otherwise = selClassesFor s

   prevVisibleRow :: Array RecordRow -> Int -> Maybe Int
   prevVisibleRow rows this
      | this <= 0 = Nothing
      | record_isDisplayable $ rows ! (this - 1) = Just (this - 1)
      | otherwise = prevVisibleRow rows (this - 1)

   nextVisibleRow :: Array RecordRow -> Int -> Maybe Int
   nextVisibleRow rows this
      | this == length rows - 1 = Nothing
      | record_isDisplayable $ rows ! (this + 1) = Just (this + 1)
      | otherwise = nextVisibleRow rows (this + 1)

   hasRightBorder :: Array RecordRow -> Int -> Int -> Boolean
   hasRightBorder rows i j
      | j == width rows - 1 = isCellTransient rows i j
      | otherwise = isCellTransient rows i j /= isCellTransient rows i (j + 1)

   hasBottomBorder :: Array RecordRow -> Int -> Int -> Boolean
   hasBottomBorder rows i j
      | i /= -1 && (not <<< record_isDisplayable $ rows ! i) = false -- change this
      | otherwise = case nextVisibleRow rows i of
           Nothing -> isCellTransient rows i j
           Just next -> isCellTransient rows i j /= isCellTransient rows next j

-- If I try to make this local to tableViewHelpers something goes wrong, can't see why..
isCellTransient :: Array RecordRow -> Int -> Int -> Boolean
isCellTransient rows i j
   | i == -1 || j == -1 = false -- header row has j = -1 and rowKey column has i = -1
   | otherwise = isTransient <<< (unwrap tableViewHelpers).val_selState $ rows ! i ! j

instance Drawable2 TableView TableViewHelpers where
   createRootElement = createRootElement2
   setSelState = setSelState

prim :: Val (SelState 𝕊) -> String
prim (Val _ v) = v # case _ of
   Int n -> show n
   Float n -> toStringWith (fixed 2) n
   Str s -> s
   _ -> error $ "TableView only supports primitive values."

setSelState2 :: TableView -> TableViewHelpers -> EventListener -> D3.Selection -> Effect Unit
setSelState2 _ _ _ _ = do
   pure unit

createRootElement2 :: TableView -> TableViewHelpers -> D3.Selection -> String -> Effect D3.Selection
createRootElement2 (TableView { colNames, filter, rows }) _ div childId = do
   rootElement <- div # create Table [ "id" ↦ childId ]
   void $ rootElement # create Caption
      [ "class" ↦ classes [ "title-text", "table-caption" ]
      , "dominant-baseline" ↦ "middle"
      , "text-anchor" ↦ "left"
      ]
   let colNames' = [ rowKey ] <> colNames
   rootElement # createHeader colNames'
   body <- rootElement # create TBody []
   forWithIndex_ rows \i row -> do
      row' <- body # create TR [ "class" ↦ "table-row" ]
         >>= setData { i }
      forWithIndex_ ([ show (i + 1) ] <> (row <#> prim)) \j value -> do
         cell <- row' # create TD [ "class" ↦ if j >= 0 then "table-cell" else "" ]
         void $ cell
            # setStyles
                 [ "border-top" ↦ "1px solid transparent"
                 , "border-left" ↦ "1px solid transparent"
                 , "border-right" ↦ if j == length colNames - 1 then "1px solid transparent" else ""
                 , "border-bottom" ↦ if i == length rows - 1 then "1px solid transparent" else ""
                 ]
            >>= setText value
            >>= setData { i, j: j - 1, value, colName: colNames' ! j } -- TODO: rename "value" to "text"?
         log <$> (cell # datum)
   pure rootElement
   where
   createHeader colNames' rootElement = do
      row <- rootElement # create THead [] >>= create TR []
      for_ colNames' \colName ->
         row
            # create TH [ "class" ↦ cellClasses colName ]
            >>= setText (if colName == rowKey then if filter == Relevant then "▸" else "▾" else colName)

   cellClasses colName
      | colName == rowKey = classes [ "filter-toggle", "toggle-button" ]
      | otherwise = ""

instance Drawable TableView where
   draw rSpec figVal _ redraw = do
      draw' tableViewHelpers uiHelpers rSpec =<< selListener figVal redraw tableViewSelSetter
      where
      tableViewSelSetter :: ViewSelSetter CellIndex
      tableViewSelSetter { i, colName } = listElement i <<< field colName

--      toggleListener <- filterToggleListener filterToggler
--
--      filterToggleListener :: FilterToggler -> Effect EventListener
--      filterToggleListener toggler = eventListener (eventData >>> toggler >>> (\_ -> identity) >>> redraw)

-- convert mouse event data (here, always rowKey) to view change
type FilterToggler = String -> Endo TableView

filterToggler :: FilterToggler
filterToggler _ (TableView view) = TableView view { filter = rotate view.filter }
   where
   rotate :: Endo Filter
   rotate Everything = Interactive
   rotate Interactive = Relevant
   rotate Relevant = Everything

-- 0-based index of selected record and name of field; see data binding in .js (-1th field name is __n, the rowKey)
type CellIndex = { i :: Int, colName :: String }

-- ======================
-- boilerplate
-- ======================
derive instance Newtype TableViewHelpers _
derive instance Eq Filter
