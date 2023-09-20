module Example.Util.BMA where

import Prelude

import Data.FastVect.FastVect (Vect)
import Data.Foldable (foldl)
import Data.Int (toNumber)
import Data.Number (pow)
-- import Effect (Effect)
-- import Effect.Class.Console (logShow)

data IntInfty = IInt Int | Infty 

product :: forall a len. Semiring a => Vect len a -> a
product v = foldl (*) one v 

sum :: forall a len. Semiring a => Vect len a -> a
sum v = foldl (+) zero v

vlen :: forall a len. Vect len a -> Int
vlen xs = foldl (\count _x -> (+) 1 count) 0 xs

vlenN :: forall a len. Vect len a -> Number
vlenN = toNumber <<< vlen

mean :: forall len. Number -> Vect len Number -> Number
mean 0.0 xs = product xs `pow` (1.0 / vlenN xs)
mean p xs = ((1.0 / vlenN xs) * sum (map (\x -> pow x p) xs)) `pow` (1.0/p)

-- band_matrix :: forall x y. Int -> Int -> Int -> Matrix x y IntInfty
-- band_matrix nrows ncols slack = Matrix $ empty
    