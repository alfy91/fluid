-- | This module defines a set of combinators for pretty printing text.

module Util.Pretty
   ( Doc(..)
   , width
   , height
   , render
   , empty
   , text
   , atop
   , Stack(..)
   , vcat
   , Columns(..)
   , hcat
   , beside
   , space
   ) where

import Prelude

import Data.Array (drop, singleton, take, uncons, zipWith, head, last)
import Data.Array (length, replicate) as A
import Data.Foldable (class Foldable, foldl, foldMap, intercalate)
import Data.Maybe (Maybe(..))
import Data.Newtype (ala, class Newtype, wrap)
import Data.String as S
import Util (absurd) as U
import Util (error)

-- | A text document.
newtype Doc = Doc
   { width :: Int
   , height :: Int
   , lines :: Array String
   }

derive instance Eq Doc

width :: Doc -> Int
width (Doc doc) = doc.width

height :: Doc -> Int
height (Doc doc) = doc.height

render :: Doc -> String
render (Doc doc) = intercalate "\n" doc.lines

empty :: Doc
empty = Doc
   { width: 0
   , height: 1
   , lines: singleton ""
   }

text :: String -> Doc
text s = checkOneLine (S.split (wrap "\n") (" " <> s))

checkOneLine :: Array String -> Doc
checkOneLine xs = case uncons xs of
   Just { head: x, tail: [] } -> Doc
      { width: S.length x
      , height: 1
      , lines: singleton x
      }
   Just { head: _, tail: _ } -> error U.absurd
   Nothing -> error U.absurd

atop :: Doc -> Doc -> Doc
atop (Doc d1) (Doc d2) =
   Doc
      { width: max d1.width d2.width
      , height: d1.height + d2.height
      , lines: d1.lines <> d2.lines
      }

space :: Doc -> Doc -> Doc
space d1 d2 = d1 :<>: text " " :<>: d2

infixl 5 beside as :<>:
infixl 5 atop as .-.
infixl 5 space as :--:

helperUnwrapMaybe :: Maybe String -> String
helperUnwrapMaybe (Just x) = x
helperUnwrapMaybe (Nothing) = ""

spaces :: Int -> String
spaces n = foldl (<>) "" (A.replicate n " ")

allButLast :: Doc -> Array String
allButLast (Doc d) = take (A.length d.lines - 1) d.lines

allButFirst :: Doc -> Array String
allButFirst (Doc d) = drop 1 d.lines

firstLine :: Doc -> String
firstLine (Doc d) = helperUnwrapMaybe (head d.lines)

lastLine :: Doc -> String
lastLine (Doc d) = helperUnwrapMaybe (last d.lines)

-- takes all but the first lines of d2 so say e.g. [s1, s2] and spaces returns "  " (length of last line of d1) and we do ["  ", " "]
-- we then zip this with all but the first line of d2 so we have indented the document by the length of the last line of d1
indentedExpression :: Doc -> Doc -> Array String
indentedExpression (Doc d1) (Doc d2) =
   zipWith (<>)
      ( A.replicate (A.length (allButFirst (Doc d2)))
           (spaces (S.length (lastLine (Doc d1))))
      )
      (allButFirst (Doc d2))

beside :: Doc -> Doc -> Doc
beside (Doc d1) (Doc d2) = Doc { width: d1.width + d2.width, height: d1.height + d2.height, lines: allButLast (Doc d1) <> (singleton (lastLine (Doc d1) <> "" <> firstLine (Doc d2))) <> indentedExpression (Doc d1) (Doc d2) }

hcat :: forall f. Foldable f => f Doc -> Doc
hcat = ala Columns foldMap

vcat :: forall f. Foldable f => f Doc -> Doc
vcat = ala Stack foldMap

-- | A wrapper for `Doc` with a `Monoid` instance which stacks documents vertically.
newtype Stack = Stack Doc

derive instance Newtype Stack _

instance Semigroup Stack where
   append (Stack d1) (Stack d2) = Stack (d1 `atop` d2)

instance Monoid Stack where
   mempty = Stack empty

-- | A wrapper for `Doc` with a `Monoid` instance which stacks documents in columns.
newtype Columns = Columns Doc

derive instance Newtype Columns _

instance Semigroup Columns where
   append (Columns d1) (Columns d2) = Columns (d1 `beside` d2)

instance Monoid Columns where
   mempty = Columns empty
