module App.View.TableView where

import Prelude

import App.Util (SelState, 𝕊(..), classes, getPersistent, getTransient, isInert, isTransient, selClasses, selClassesFor)
import App.Util.Selector (ViewSelSetter, field, listElement)
import App.View.Util (class Drawable, class Drawable2, draw', registerMouseListeners, selListener, uiHelpers)
import App.View.Util.D3 (ElementType(..), classed, create, datum, select, selectAll, setData, setStyles, setText)
import App.View.Util.D3 as D3
import Bind ((↦))
import Data.Array (filter, head, null, sort)
import Data.Foldable (for_)
import Data.FoldableWithIndex (forWithIndex_)
import Data.List (filterM, fromFoldable)
import Data.Maybe (Maybe(..))
import Data.Number.Format (fixed, toStringWith)
import Data.Set (toUnfoldable)
import Dict (Dict)
import Effect (Effect)
import Util (Endo, definitely', error, length, (!))
import Util.Map (get, keys)
import Val (Array2, BaseVal(..), Val(..))
import Web.Event.EventTarget (EventListener)

type Record' = Array (Val (SelState 𝕊)) -- somewhat anomalous, as elsewhere we have Selectables

data Filter = Everything | Interactive | Relevant

-- homogeneous array of records with fields of primitive type; each row has same length as colNames
newtype TableView = TableView
   { title :: String
   , filter :: Filter
   , colNames :: Array String
   , rows :: Array Record' -- would list make more sense given the filtering?
   }

-- helpers to decompose array of records represented as dictionaries into colNames and rows
headers :: Array (Dict (Val (SelState 𝕊))) -> Array String
headers records = sort <<< toUnfoldable <<< keys <<< definitely' $ head records

arrayDictToArray2 :: forall a. Array String -> Array (Dict a) -> Array2 a
arrayDictToArray2 = map <<< flip (map <<< flip get)

defaultFilter :: Filter
defaultFilter = Interactive

rowKey :: String
rowKey = "__n"

cell_selClassesFor :: String -> SelState 𝕊 -> String
cell_selClassesFor colName s
   | colName == rowKey = ""
   | otherwise = selClassesFor s

record_isVisible :: Record' -> Boolean
record_isVisible r =
   not <<< null $ flip filter r \(Val α _) -> visible defaultFilter α
   where
   visible :: Filter -> SelState 𝕊 -> Boolean
   visible Everything = const true
   visible Interactive = not isInert
   visible Relevant = not (isNone || isInert)

   isNone :: SelState 𝕊 -> Boolean
   isNone a = getPersistent a == None && getTransient a == None

instance Drawable2 TableView where
   createRootElement = createRootElement
   setSelState = setSelState

prim :: Val (SelState 𝕊) -> String
prim (Val _ v) = v # case _ of
   Int n -> show n
   Float n -> toStringWith (fixed 2) n
   Str s -> s
   _ -> error $ "TableView only supports primitive values."

setSelState :: TableView -> EventListener -> D3.Selection -> Effect Unit
setSelState (TableView { title, rows }) redraw rootElement = do
   cells <- rootElement # selectAll ".table-cell"
   for_ cells \cell -> do
      { i, j, colName } :: CellIndex <- datum cell
      if i == -1 || j == -1 then pure unit
      else cell # classed selClasses false
         >>= classed (cell_selClassesFor colName (rows ! i ! j # \(Val α _) -> α)) true
         >>= registerMouseListeners redraw
      cell # classed "has-right-border" (hasRightBorder i j)
         >>= classed "has-bottom-border" (hasBottomBorder i j)
   hideRecords >>= setCaption
   where
   hideRecords :: Effect Int
   hideRecords = do
      rows' <- rootElement # selectAll ".table-row"
      hidden <- flip filterM (fromFoldable rows') \row -> do
         { i } <- datum row
         pure $ not (record_isVisible (rows ! i))
      for_ hidden $ classed "hidden" true
      pure (length hidden)

   setCaption :: Int -> Effect Unit
   setCaption numHidden = do
      let caption = title <> " (" <> show (length rows - numHidden) <> " of " <> show (length rows) <> ")"
      void $ rootElement # select ".table-caption" >>= setText caption

   {-
   width :: Array Record' -> Int
   width = head >>> definitely' >>> length
-}
   visiblePred :: Int -> Maybe Int
   visiblePred i
      | i <= 0 = Nothing
      | record_isVisible $ rows ! (i - 1) = Just (i - 1)
      | otherwise = visiblePred (i - 1)

   visibleSucc :: Int -> Maybe Int
   visibleSucc i
      | i == length rows - 1 = Nothing
      | record_isVisible $ rows ! (i + 1) = Just (i + 1)
      | otherwise = visibleSucc (i + 1)

   hasRightBorder :: Int -> Int -> Boolean
   hasRightBorder _ _ = false

   hasBottomBorder :: Int -> Int -> Boolean
   hasBottomBorder i j = virtualTopBorder || virtualBottomBorder
      where
      virtualTopBorder = i < length rows - 1 && isCellTransient (i + 1) j
      virtualBottomBorder = case visibleSucc i of
         Nothing -> isCellTransient i j -- my own bottom-border
         Just i' -> case visiblePred i' of
            Nothing -> false -- no visible cell for me to provide bottom-border for
            Just i'' ->
               isCellTransient i'' j && i == i' - 1 -- virtual bottom-border for a cell above me

   isCellTransient :: Int -> Int -> Boolean
   isCellTransient i j
      | i == -1 || j == -1 = false -- do we need to allow for these cases?
      | otherwise = isTransient <<< (\(Val α _) -> α) $ rows ! i ! j

createRootElement :: TableView -> D3.Selection -> String -> Effect D3.Selection
createRootElement (TableView { colNames, filter, rows }) div childId = do
   rootElement <- div # create Table [ "id" ↦ childId ]
   void $ rootElement # create Caption
      [ classes [ "title-text", "table-caption" ]
      , "dominant-baseline" ↦ "middle"
      , "text-anchor" ↦ "left"
      ]
   let colNames' = [ rowKey ] <> colNames
   rootElement # createHeader colNames'
   body <- rootElement # create TBody []
   forWithIndex_ rows \i row -> do
      row' <- body # create TR [ classes [ "table-row" ] ] >>= setData { i }
      forWithIndex_ ([ show (i + 1) ] <> (row <#> prim)) \j value -> do
         cell <- row' # create TD [ classes if j >= 0 then [ "table-cell" ] else [] ]
         void $ cell
            # setStyles
                 [ "border-top" ↦ transparentBorder
                 , "border-left" ↦ transparentBorder
                 , "border-right" ↦ if j == length colNames' - 1 then transparentBorder else ""
                 , "border-bottom" ↦ if i == length rows - 1 then transparentBorder else ""
                 ]
            >>= setText value
            >>= setData { i, j: j - 1, value, colName: colNames' ! j } -- TODO: rename "value" to "text"?
   pure rootElement
   where
   transparentBorder = "1px solid transparent"

   createHeader colNames' rootElement = do
      row <- rootElement # create THead [] >>= create TR []
      forWithIndex_ colNames' \j colName -> do
         let value = if colName == rowKey then if filter == Relevant then "▸" else "▾" else colName
         row
            # create TH [ classes ([ "table-cell" ] <> cellClasses colName) ]
            >>= setText value
            >>= setData { i: -1, j: j - 1, value, colName: colNames' ! j }

   cellClasses colName
      | colName == rowKey = [ "filter-toggle", "toggle-button" ]
      | otherwise = []

instance Drawable TableView where
   draw rSpec figVal _ redraw = do
      draw' uiHelpers rSpec =<< selListener figVal redraw tableViewSelSetter
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

-- 0-based index of selected record and name of field; -1th field name is "__n" (rowKey)
type CellIndex = { i :: Int, j :: Int, colName :: String, value :: String }

-- ======================
-- boilerplate
-- ======================
derive instance Eq Filter
