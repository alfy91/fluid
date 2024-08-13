module App.View.MatrixView where

import Prelude hiding (absurd)

import App.Util (ReactState, 𝕊, ViewSelector, Selectable)
import App.Util.Selector (matrixElement)
import App.View.Util (class Drawable, Renderer, selListener, uiHelpers)
import Primitive (int, unpack)
import Util ((×))
import Val (Array2, MatrixRep(..))

--  (Rendered) matrices are required to have element type Int for now.
type IntMatrix = { cells :: Array2 (Selectable Int), i :: Int, j :: Int }

newtype MatrixView = MatrixView { title :: String, matrix :: IntMatrix }

foreign import drawMatrix :: Renderer MatrixView Unit

instance Drawable MatrixView Unit where
   draw divId suffix redraw view viewState =
      drawMatrix { uiHelpers, divId, suffix, view, viewState } =<< selListener redraw matrixViewSelector
      where
      matrixViewSelector :: ViewSelector MatrixCellCoordinate
      matrixViewSelector { i, j } = matrixElement i j

matrixRep :: MatrixRep (ReactState 𝕊) -> IntMatrix
matrixRep (MatrixRep (vss × (i × _) × (j × _))) =
   { cells: (unpack int <$> _) <$> vss, i, j }

-- 1-based indices of selected cell; see data binding in .js
type MatrixCellCoordinate = { i :: Int, j :: Int }
