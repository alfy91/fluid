module App.View.LinkedText where

import Prelude

import App.Util (class Reflect, SelState, Selectable, 𝕊, from)
import App.Util.Selector (linkedText, listElement, ViewSelSetter)
import App.View.Util (class Drawable, Renderer, selListener, uiHelpers)
import Primitive (string, unpack)
import Val (Val)

foreign import drawLinkedText :: LinkedTextHelpers -> Renderer LinkedText

type LinkedTextHelpers = {}
newtype LinkedText = LinkedText (Array (Selectable String))

drawLinkedText' :: Renderer LinkedText
drawLinkedText' = drawLinkedText {}

linkedTextHelpers :: LinkedTextHelpers
linkedTextHelpers =
   {}

instance Drawable LinkedText where
   draw rSpec figVal _ redraw =
      drawLinkedText linkedTextHelpers uiHelpers rSpec =<< selListener figVal redraw linkedTextSelector
      where
      linkedTextSelector :: ViewSelSetter LinkedTextElem
      linkedTextSelector { i } = linkedText <<< listElement i

instance Reflect (Val (SelState 𝕊)) LinkedText where
   from r = LinkedText (unpack string <$> from r)

-- unpackedStringify :: forall a. Tuple (Int + Number + String) a -> Tuple String a
-- unpackedStringify (Tuple x y) = Tuple (stringify x) y

-- stringify :: (Int + Number + String) -> String
-- stringify (Left n) = toString $ toNumber n
-- stringify (Right (Left n)) = toString n
-- stringify (Right (Right n)) = n

type LinkedTextElem = { i :: Int }
