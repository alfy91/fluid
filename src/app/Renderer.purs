module App.Renderer where

import Prelude
import Effect (Effect)
import Lattice (𝔹)
import Primitive (match, match_fwd)
import Util (type (×), (×))
import Val (Array2, MatrixRep, Val)

foreign import drawMatrix :: Array2 (Int × 𝔹) -> Int -> Int -> Effect Unit

-- Will want to generalise to arrays of "drawable values".
toIntArray :: Array2 (Val 𝔹) -> Array2 (Int × 𝔹)
toIntArray = (<$>) ((<$>) match)

-- second component of elements is original value
toIntArray2 :: Array2 (Val 𝔹 × Val 𝔹) -> Array2 (Int × 𝔹)
toIntArray2 = (<$>) ((<$>) match_fwd)

-- Inputs are matrices; second is original (unsliced) value.
renderMatrix :: Val 𝔹 × Val 𝔹 -> Effect Unit
renderMatrix = match_fwd >>> renderMatrix'
   where
   renderMatrix' :: MatrixRep 𝔹 × 𝔹 -> Effect Unit
   renderMatrix' (vss × (i × _) × (j × _) × _) = drawMatrix (toIntArray vss) i j
