module App.View.Util where

import Prelude

import App.Util (ReactState, Selectable, 𝕊, selClasses, selClassesFor, selectionEventData)
import App.Util.Selector (ViewSelSetter)
import Bind (Bind, Var)
import Data.Maybe (Maybe)
import Data.Tuple (fst, snd, uncurry)
import Dict (Dict)
import Effect (Effect)
import GaloisConnection (GaloisConnection)
import Lattice (𝔹, Raw, (∨))
import Module (File)
import SExpr as S
import Util (type (×), Endo, Setter)
import Val (Env, Val)
import Web.Event.EventTarget (EventListener, eventListener)

type HTMLId = String
type Redraw = Endo Fig -> Effect Unit

newtype View = View (forall r. (forall a. Drawable a => a -> r) -> r)

pack :: forall a. Drawable a => a -> View
pack x = View \k -> k x

unpack :: forall r. View -> (forall a. Drawable a => a -> r) -> r
unpack (View vw) k = vw k

selListener :: forall a. Setter Fig (Val (ReactState 𝔹)) -> Redraw -> ViewSelSetter a -> Effect EventListener
selListener figVal redraw selector =
   eventListener (selectionEventData >>> uncurry (selector) >>> figVal >>> redraw)

class Drawable a where
   draw :: RendererSpec a -> Setter Fig (Val (ReactState 𝔹)) -> Setter Fig View -> Redraw -> Effect Unit

drawView :: RendererSpec View -> Setter Fig (Val (ReactState 𝔹)) -> Setter Fig View -> Redraw -> Effect Unit
drawView rSpec@{ view: vw } figVal figView redraw =
   unpack vw (\view -> draw (rSpec { view = view }) figVal figView redraw)

-- Heavily curried type isn't convenient for FFI
type RendererSpec a =
   { divId :: HTMLId
   , suffix :: String
   , view :: a
   }

type Renderer a = UIHelpers -> RendererSpec a -> EventListener -> Effect Unit

type UIHelpers =
   { val :: forall a. Selectable a -> a
   , selState :: forall a. Selectable a -> ReactState 𝕊
   , join :: ReactState 𝕊 -> ReactState 𝕊 -> ReactState 𝕊
   , selClasses :: String
   , selClassesFor :: ReactState 𝕊 -> String
   }

uiHelpers :: UIHelpers
uiHelpers =
   { val: fst
   , selState: snd
   , join: (∨)
   , selClasses
   , selClassesFor
   }

type FigSpec =
   { imports :: Array String
   , datasets :: Array (Bind String)
   , file :: File
   , inputs :: Array Var
   }

data Direction = LinkedInputs | LinkedOutputs

type Fig =
   { spec :: FigSpec
   , s :: Raw S.Expr
   , γ :: Env (ReactState 𝔹)
   , v :: Val (ReactState 𝔹)
   , gc :: GaloisConnection (Val (ReactState 𝔹) × Env (ReactState 𝔹)) (Val (ReactState 𝔹))
   , gc_dual :: GaloisConnection (Env (ReactState 𝔹) × Val (ReactState 𝔹)) (Env (ReactState 𝔹))
   , dir :: Direction
   , in_views :: Dict (Maybe View) -- strengthen this
   , out_view :: Maybe View
   }

-- ======================
-- boilerplate
-- ======================

derive instance Eq Direction
