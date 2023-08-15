module Graph.Slice where

import Data.Foldable (class Foldable)
import Prelude hiding (add)
import Data.List (List(..), (:))
import Data.List as L
import Data.Tuple (fst)
import Expr (Expr)
import Graph (class Graph, Edge, Vertex, add, addIn, addOut, discreteG, elem, inEdges, inEdges', outEdges, outEdges', outN, remove)
import Set (class Set, singleton, empty, unions, member)
import Util (type (×), (×))
import Val (Env)

bwdSlice :: forall g s. Set s Vertex => Graph g s => s Vertex -> g -> g
bwdSlice αs g' = bwdEdges g' (discreteG αs) (outEdges g' αs)

bwdEdges :: forall g s. Graph g s => g -> g -> List Edge -> g
bwdEdges g' g ((α × β) : es) =
   bwdEdges g' (addOut α β g) $
      es <> if elem g β then Nil else L.fromFoldable (outEdges' g' β)
bwdEdges _ g Nil = g

fwdSlice :: forall g s. Graph g s => s Vertex -> g -> g
fwdSlice αs g' = fst $ fwdEdges g' (discreteG αs) mempty (inEdges g' αs)

fwdEdges :: forall g s. Graph g s => g -> g -> g -> List Edge -> g × g
fwdEdges g' g h ((α × β) : es) = fwdEdges g' g'' h' es
   where
   g'' × h' = fwdVertex g' g (addIn α β h) α
fwdEdges _ currSlice pending Nil = currSlice × pending

fwdVertex :: forall g s. Set s Vertex => Graph g s => g -> g -> g -> Vertex -> g × g
fwdVertex g' g h α =
   if αs == outN g' α then
      fwdEdges g' (add α αs g) (remove α h) (inEdges' g' α)
   else g × h
   where
   αs = outN h α

selectVertices :: forall s f. Set s Vertex => Apply f => Foldable f => f Vertex -> f Boolean -> s Vertex
selectVertices vα v𝔹 = αs_v
   where
   αs_v = unions (asSet <$> v𝔹 <*> vα)

{-
selectVertices' :: forall s. Set s Vertex => Env Vertex × Expr Vertex -> Env Boolean × Expr Boolean -> s Vertex
selectVertices' (γα × eα) (γ𝔹 × e𝔹) = union αs_e αs_γ
   where
   αs_e = gather (asSet <$> e𝔹 <*> eα)
   αs_γ = gather (gather <$> D.values (D.lift2 asSet γ𝔹 γα) :: List (s Vertex))
-}

select𝔹s :: forall s f. Set s Vertex => Functor f => f Vertex -> s Vertex -> f Boolean
select𝔹s vα αs = v𝔹
   where
   v𝔹 = map (flip member αs) vα

select𝔹s' :: forall s. Set s Vertex => Env Vertex × Expr Vertex -> s Vertex -> Env Boolean × Expr Boolean
select𝔹s' (γα × eα) αs = γ𝔹 × e𝔹
   where
   γ𝔹 = map (flip select𝔹s αs) γα
   e𝔹 = select𝔹s eα αs

asSet :: forall s. Set s Vertex => Boolean -> Vertex -> s Vertex
asSet true = singleton
asSet false = const empty
