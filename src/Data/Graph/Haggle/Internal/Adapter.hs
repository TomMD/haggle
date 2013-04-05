{-# LANGUAGE TypeFamilies #-}
-- | This internal module implements code shared between all of the
-- adapter interfaces.  The adapters add support for vertex and edge
-- labels without modifications to the underlying graph.  Any graph
-- implementing the 'MGraph' interface can have labels added with
-- these adapters.
--
-- Analogous adapters will be added for the pure graph interface, too.
module Data.Graph.Haggle.Internal.Adapter (
  -- * Types
  LabeledMGraph(..),
  LabeledGraph(..),
  -- * Mutable graph API
  newLabeledGraph,
  newSizedLabeledGraph,
  -- * Immutable graph API
  fromEdgeList,
  -- * Helpers
  ensureEdgeLabelStorage,
  ensureNodeLabelStorage
  ) where

import Control.Monad ( liftM )
import Control.Monad.Primitive
import Data.PrimRef
import Data.Vector ( MVector, Vector )
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import qualified Data.Graph.Haggle as I
import qualified Data.Graph.Haggle.Internal.Basic as I

-- | An adapter adding support for both vertex and edge labels for mutable
-- graphs.
data LabeledMGraph g nl el m =
  LMG { rawMGraph :: g m
      , nodeLabelStorage :: PrimRef m (MVector (PrimState m) nl)
      , edgeLabelStorage :: PrimRef m (MVector (PrimState m) el)
      }

-- | An adapter adding support for both vertex and edge labels for immutable
-- graphs.
data LabeledGraph g nl el =
  LG { rawGraph :: g
     , nodeLabelStore :: Vector nl
     , edgeLabelStore :: Vector el
     }

newLabeledGraph :: (PrimMonad m, I.MGraph g)
                => m (g m)
                -> m (LabeledMGraph g nl el m)
newLabeledGraph newG = do
  g <- newG
  nstore <- MV.new 128
  nref <- newPrimRef nstore
  estore <- MV.new 128
  eref <- newPrimRef estore
  return LMG { rawMGraph = g
             , nodeLabelStorage = nref
             , edgeLabelStorage = eref
             }

newSizedLabeledGraph :: (PrimMonad m, I.MGraph g)
                     => (Int -> Int -> m (g m))
                     -> Int
                     -> Int
                     -> m (LabeledMGraph g nl el m)
newSizedLabeledGraph newG szVertices szEdges = do
  g <- newG szVertices szEdges
  nstore <- MV.new szVertices
  nref <- newPrimRef nstore
  estore <- MV.new szEdges
  eref <- newPrimRef estore
  return LMG { rawMGraph = g
             , nodeLabelStorage = nref
             , edgeLabelStorage = eref
             }

addLabeledVertex :: (PrimMonad m, I.MGraph g, I.MAddVertex g)
                 => LabeledMGraph g nl el m
                 -> nl
                 -> m I.Vertex
addLabeledVertex lg nl = do
  v <- I.addVertex (rawMGraph lg)
  ensureNodeLabelStorage lg
  nlVec <- readPrimRef (nodeLabelStorage lg)
  MV.write nlVec (I.vertexId v) nl
  return v

getEdgeLabel :: (PrimMonad m, I.MGraph g)
             => LabeledMGraph g nl el m
             -> I.Edge
             -> m (Maybe el)
getEdgeLabel lg e = do
  nEs <- I.countEdges (rawMGraph lg)
  case I.edgeId e >= nEs of
    True -> return Nothing
    False -> do
      elVec <- readPrimRef (edgeLabelStorage lg)
      Just `liftM` MV.read elVec (I.edgeId e)

getVertexLabel :: (PrimMonad m, I.MGraph g)
               => LabeledMGraph g nl el m
               -> I.Vertex
               -> m (Maybe nl)
getVertexLabel lg v = do
  nNs <- I.countVertices (rawMGraph lg)
  case I.vertexId v >= nNs of
    True -> return Nothing
    False -> do
      nlVec <- readPrimRef (nodeLabelStorage lg)
      Just `liftM` MV.read nlVec (I.vertexId v)

addLabeledEdge :: (PrimMonad m, I.MGraph g, I.MAddEdge g)
               => LabeledMGraph g nl el m
               -> I.Vertex
               -> I.Vertex
               -> el
               -> m (Maybe I.Edge)
addLabeledEdge lg src dst el = do
  e <- I.addEdge (rawMGraph lg) src dst
  case e of
    Nothing -> return e
    Just e' -> do
      ensureEdgeLabelStorage lg
      elVec <- readPrimRef (edgeLabelStorage lg)
      MV.write elVec (I.edgeId e') el
      return e

getSuccessors :: (PrimMonad m, I.MGraph g)
              => LabeledMGraph g nl el m
              -> I.Vertex
              -> m [I.Vertex]
getSuccessors lg = I.getSuccessors (rawMGraph lg)
{-# INLINE getSuccessors #-}

getOutEdges :: (PrimMonad m, I.MGraph g)
            => LabeledMGraph g nl el m -> I.Vertex -> m [I.Edge]
getOutEdges lg = I.getOutEdges (rawMGraph lg)
{-# INLINE getOutEdges #-}

countVertices :: (PrimMonad m, I.MGraph g) => LabeledMGraph g nl el m -> m Int
countVertices = I.countVertices . rawMGraph
{-# INLINE countVertices #-}

countEdges :: (PrimMonad m, I.MGraph g) => LabeledMGraph g nl el m -> m Int
countEdges = I.countEdges . rawMGraph
{-# INLINE countEdges #-}

getPredecessors :: (PrimMonad m, I.MBidirectional g)
                => LabeledMGraph g nl el m -> I.Vertex -> m [I.Vertex]
getPredecessors lg = I.getPredecessors (rawMGraph lg)
{-# INLINE getPredecessors #-}

getInEdges :: (PrimMonad m, I.MBidirectional g)
           => LabeledMGraph g nl el m -> I.Vertex -> m [I.Edge]
getInEdges lg = I.getInEdges (rawMGraph lg)
{-# INLINE getInEdges #-}

checkEdgeExists :: (PrimMonad m, I.MGraph g)
                => LabeledMGraph g nl el m
                -> I.Vertex
                -> I.Vertex
                -> m Bool
checkEdgeExists lg = I.checkEdgeExists (rawMGraph lg)
{-# INLINE checkEdgeExists #-}

freeze :: (PrimMonad m, I.MGraph g)
       => LabeledMGraph g nl el m
       -> m (LabeledGraph (I.ImmutableGraph g) nl el)
freeze lg = do
  g' <- I.freeze (rawMGraph lg)
  nc <- I.countVertices (rawMGraph lg)
  ec <- I.countEdges (rawMGraph lg)
  ns <- readPrimRef (nodeLabelStorage lg)
  es <- readPrimRef (edgeLabelStorage lg)
  ns' <- V.freeze (MV.take nc ns)
  es' <- V.freeze (MV.take ec es)
  return LG { rawGraph = g'
            , nodeLabelStore = ns'
            , edgeLabelStore = es'
            }

instance (I.MGraph g) => I.MGraph (LabeledMGraph g nl el) where
  type ImmutableGraph (LabeledMGraph g nl el) = LabeledGraph (I.ImmutableGraph g) nl el
  getSuccessors = getSuccessors
  getOutEdges = getOutEdges
  countEdges = countEdges
  countVertices = countVertices
  checkEdgeExists = checkEdgeExists
  freeze = freeze

instance (I.MBidirectional g) => I.MBidirectional (LabeledMGraph g nl el) where
  getPredecessors = getPredecessors
  getInEdges = getInEdges

instance (I.MAddEdge g) => I.MLabeledEdge (LabeledMGraph g nl el) where
  type MEdgeLabel (LabeledMGraph g nl el) = el
  getEdgeLabel = getEdgeLabel
  addLabeledEdge = addLabeledEdge

instance (I.MAddVertex g) => I.MLabeledVertex (LabeledMGraph g nl el) where
  type MVertexLabel (LabeledMGraph g nl el) = nl
  getVertexLabel = getVertexLabel
  addLabeledVertex = addLabeledVertex

vertices :: (I.Graph g) => LabeledGraph g nl el -> [I.Vertex]
vertices = I.vertices . rawGraph
{-# INLINE vertices #-}

edges :: (I.Graph g) => LabeledGraph g nl el -> [I.Edge]
edges = I.edges . rawGraph
{-# INLINE edges #-}

successors :: (I.Graph g) => LabeledGraph g nl el -> I.Vertex -> [I.Vertex]
successors lg = I.successors (rawGraph lg)
{-# INLINE successors #-}

outEdges :: (I.Graph g) => LabeledGraph g nl el -> I.Vertex -> [I.Edge]
outEdges lg = I.outEdges (rawGraph lg)
{-# INLINE outEdges #-}

edgeExists :: (I.Graph g) => LabeledGraph g nl el -> I.Vertex -> I.Vertex -> Bool
edgeExists lg = I.edgeExists (rawGraph lg)
{-# INLINE edgeExists #-}

maxVertexId :: (I.Graph g) => LabeledGraph g nl el -> Int
maxVertexId = I.maxVertexId . rawGraph
{-# INLINE maxVertexId #-}

isEmpty :: (I.Graph g) => LabeledGraph g nl el -> Bool
isEmpty = I.isEmpty . rawGraph
{-# INLINE isEmpty #-}

thaw :: (PrimMonad m, I.Graph g)
     => LabeledGraph g nl el
     -> m (LabeledMGraph (I.MutableGraph g) nl el m)
thaw lg = do
  g' <- I.thaw (rawGraph lg)
  nlVec <- V.thaw (nodeLabelStore lg)
  elVec <- V.thaw (edgeLabelStore lg)
  nref <- newPrimRef nlVec
  eref <- newPrimRef elVec
  return LMG { rawMGraph = g'
             , nodeLabelStorage = nref
             , edgeLabelStorage = eref
             }

instance (I.Graph g) => I.Graph (LabeledGraph g nl el) where
  type MutableGraph (LabeledGraph g nl el) = LabeledMGraph (I.MutableGraph g) nl el
  vertices = vertices
  edges = edges
  successors = successors
  outEdges = outEdges
  edgeExists = edgeExists
  maxVertexId = maxVertexId
  isEmpty = isEmpty
  thaw = thaw

predecessors :: (I.Bidirectional g) => LabeledGraph g nl el -> I.Vertex -> [I.Vertex]
predecessors lg = I.predecessors (rawGraph lg)
{-# INLINE predecessors #-}

inEdges :: (I.Bidirectional g) => LabeledGraph g nl el -> I.Vertex -> [I.Edge]
inEdges lg = I.inEdges (rawGraph lg)
{-# INLINE inEdges #-}

instance (I.Bidirectional g) => I.Bidirectional (LabeledGraph g nl el) where
  predecessors = predecessors
  inEdges = inEdges

edgeLabel :: LabeledGraph g nl el -> I.Edge -> Maybe el
edgeLabel lg e = edgeLabelStore lg V.!? I.edgeId e
{-# INLINE edgeLabel #-}

instance I.HasEdgeLabel (LabeledGraph g nl el) where
  type EdgeLabel (LabeledGraph g nl el) = el
  edgeLabel = edgeLabel

vertexLabel :: LabeledGraph g nl el -> I.Vertex -> Maybe nl
vertexLabel lg v = nodeLabelStore lg V.!? I.vertexId v
{-# INLINE vertexLabel #-}

instance I.HasVertexLabel (LabeledGraph g nl el) where
  type VertexLabel (LabeledGraph g nl el) = nl
  vertexLabel = vertexLabel



-- | Construct a graph from a labeled list of edges.  The node endpoint values
-- are used as vertex labels, and the last element of the triple is used as an
-- edge label.
fromEdgeList :: (Eq a, Ord a, I.Graph g) => [(a, a, b)] -> g
fromEdgeList = undefined

-- Helpers

ensureEdgeLabelStorage :: (PrimMonad m, I.MGraph g)
                       => LabeledMGraph g nl el m -> m ()
ensureEdgeLabelStorage lg = do
  elVec <- readPrimRef (edgeLabelStorage lg)
  edgeCount <- I.countEdges (rawMGraph lg)
  let cap = MV.length elVec
  case cap > edgeCount of
    True -> return ()
    False -> do
      elVec' <- MV.grow elVec cap
      writePrimRef (edgeLabelStorage lg) elVec'

ensureNodeLabelStorage :: (PrimMonad m, I.MGraph g)
                       => LabeledMGraph g nl el m -> m ()
ensureNodeLabelStorage lg = do
  nlVec <- readPrimRef (nodeLabelStorage lg)
  vertCount <- I.countVertices (rawMGraph lg)
  let cap = MV.length nlVec
  case cap > vertCount of
    True -> return ()
    False -> do
      nlVec' <- MV.grow nlVec cap
      writePrimRef (nodeLabelStorage lg) nlVec'
