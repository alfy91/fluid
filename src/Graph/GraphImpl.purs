module Graph.GraphImpl where

import Prelude

import Control.Monad.Rec.Class (Step(..), tailRecM)
import Control.Monad.ST (ST)
import Data.Filterable (filter)
import Data.Foldable (foldM, sequence_)
import Data.Graph as G
import Data.List (List(..), reverse, (:))
import Data.List as L
import Data.Map as M
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.Newtype (unwrap)
import Data.Profunctor.Strong ((***))
import Data.Set (Set, insert)
import Data.Set as Set
import Data.Tuple (fst, snd)
import Dict (Dict)
import Dict as D
import Foreign.Object (runST)
import Foreign.Object.ST (STObject)
import Foreign.Object.ST as OST
import Graph (class Graph, class Vertices, Direction(..), HyperEdge, Vertex(..), op, outN)
import Test.Util.Debug (checking)
import Util (type (×), assertWhen, definitely, error, singleton, (×))

-- Maintain out neighbours and in neighbours as separate adjacency maps with a common domain.
type AdjMap = Dict (Set Vertex)

data GraphImpl = GraphImpl
   { out :: AdjMap
   , in :: AdjMap
   , sinks :: Set Vertex
   , sources :: Set Vertex
   , vertices :: Set Vertex
   }

instance Eq GraphImpl where
   eq (GraphImpl g) (GraphImpl g') = g.out == g'.out

-- Dict-based implementation, efficient because Graph doesn't require any update operations.
instance Graph GraphImpl where
   outN (GraphImpl g) α = D.lookup (unwrap α) g.out # definitely "in graph"
   inN g = outN (op g)
   elem α (GraphImpl g) = isJust (D.lookup (unwrap α) g.out)
   size (GraphImpl g) = D.size g.out
   sinks (GraphImpl g) = g.sinks
   sources (GraphImpl g) = g.sources
   op (GraphImpl g) = GraphImpl { out: g.in, in: g.out, sinks: g.sources, sources: g.sinks, vertices: g.vertices }
   empty = GraphImpl { out: D.empty, in: D.empty, sinks: mempty, sources: mempty, vertices: mempty }

   fromEdgeList dir αs es =
      GraphImpl { out, in: in_, sinks: sinks' out, sources: sinks' in_, vertices }
      where
      es' = if dir == Fwd then reverse es else es
      out = runST (outMap αs es')
      in_ = runST (inMap αs es')
      vertices = Set.fromFoldable $ Set.map Vertex $ D.keys out

   -- PureScript also provides a graph implementation. Delegate to that for now.
   topologicalSort (GraphImpl g) =
      G.topologicalSort (G.fromMap (M.fromFoldable (kvs <#> (Vertex *** (unit × _)))))
      where
      kvs :: Array (String × List Vertex)
      kvs = D.toUnfoldable (g.out <#> Set.toUnfoldable)

instance Vertices GraphImpl where
   vertices (GraphImpl g) = g.vertices

-- Naive implementation based on Dict.filter fails with stack overflow on graphs with ~20k vertices.
-- This is better but still slow if there are thousands of sinks.
sinks' :: AdjMap -> Set Vertex
sinks' m = D.toArrayWithKey (×) m
   # filter (snd >>> Set.isEmpty)
   <#> (fst >>> Vertex)
   # Set.fromFoldable

-- In-place update of mutable object to calculate opposite adjacency map.
type MutableAdjMap r = STObject r (Set Vertex)

assertPresent :: forall r. MutableAdjMap r -> Vertex -> ST r Unit
assertPresent acc (Vertex α) = do
   present <- OST.peek α acc <#> isJust
   assertWhen checking.edgeListSorted (α <> " is an existing vertex") (\_ -> present) $ pure unit

addIfMissing :: forall r. STObject r (Set Vertex) -> Vertex -> ST r (MutableAdjMap r)
addIfMissing acc (Vertex β) = do
   OST.peek β acc >>= case _ of
      Nothing -> OST.poke β mempty acc
      Just _ -> pure acc

init :: forall r. Set Vertex -> ST r (MutableAdjMap r)
init αs =
   OST.new >>= flip (foldM (\acc (Vertex α) -> OST.poke α mempty acc)) αs

outMap :: forall r. Set Vertex -> List HyperEdge -> ST r (MutableAdjMap r)
outMap αs es = do
   out <- init αs
   tailRecM addEdges (es × out)
   where
   addEdges :: List HyperEdge × MutableAdjMap _ -> ST _ _
   addEdges (Nil × acc) = pure $ Done acc
   addEdges (((Vertex α × βs) : es') × acc) = do
      ok <- OST.peek α acc <#> maybe true (_ == mempty)
      if ok then do
         sequence_ $ assertPresent acc <$> (L.fromFoldable βs)
         acc' <- OST.poke α βs acc >>= flip (foldM addIfMissing) βs
         pure $ Loop (es' × acc')
      else
         error $ "Duplicate edge list entry for " <> show α

inMap :: forall r. Set Vertex -> List HyperEdge -> ST r (MutableAdjMap r)
inMap αs es = do
   in_ <- init αs
   tailRecM addEdges (es × in_)
   where
   addEdges :: List HyperEdge × MutableAdjMap _ -> ST _ _
   addEdges (Nil × acc) = pure $ Done acc
   addEdges (((α × βs) : es') × acc) = do
      acc' <- foldM (addEdge α) acc βs >>= flip addIfMissing α
      pure $ Loop (es' × acc')

   addEdge :: Vertex -> MutableAdjMap _ -> Vertex -> ST _ _
   addEdge α acc (Vertex β) = do
      OST.peek β acc >>= case _ of
         Nothing -> OST.poke β (singleton α) acc
         Just αs' -> OST.poke β (insert α αs') acc

instance Show GraphImpl where
   show (GraphImpl g) = "GraphImpl (" <> show g.out <> " × " <> show g.in <> ")"