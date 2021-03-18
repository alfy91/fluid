module Module where

import Prelude
import Affjax (defaultRequest, printError, request)
import Affjax.ResponseFormat (string)
import Data.Either (Either(..))
import Data.HTTP.Method (Method(..))
import Data.Bifunctor (bimap)
import Effect.Aff (Aff)
import Text.Parsing.Parser (runParser)
import Bindings (Bindings(..), Var, (:+:), (↦))
import SExpr (Expr) as S
import DesugarFwd (desugarFwd, desugarModuleFwd)
import Eval (eval, eval_module)
import Lattice (𝔹)
import Parse (module_, program)
import Primitive.Defs (primitives)
import Util (MayFail, type (×), (×), error, successful)
import Util.Parse (SParser)
import Val (Env)

-- For Wrattler integration. Should not end in "/".
resourceServerUrl :: String
resourceServerUrl = "."

loadFile :: String -> String -> Aff String
loadFile folder file = do
   let url = resourceServerUrl <> "/" <> folder <> "/" <> file <> ".fld"
   result <- request (defaultRequest { url = url, method = Left GET, responseFormat = string })
   case result of
      Left err -> error (printError err)
      Right response -> pure response.body

loadModule :: String -> Env 𝔹 -> Aff (Env 𝔹)
loadModule file ρ = do
   src <- loadFile "fluid/lib" file
   pure (successful (eval_module ρ (successful (desugarModuleFwd (successful (parse src module_))))))

openWithDefaultImports :: String -> Aff (Env 𝔹 × S.Expr 𝔹)
openWithDefaultImports file =
   loadFile "fluid/example" file >>= parseWithDefaultImports

successfulParse :: forall t . String -> SParser t -> t
successfulParse src p =
   case runParser src p of
      Left parseError -> error (show parseError)
      Right t -> t

parse :: forall t . String -> SParser t -> MayFail t
parse src = bimap show identity <<< runParser src

parseWithDefaultImports :: String -> Aff (Env 𝔹 × S.Expr 𝔹)
parseWithDefaultImports src = do
   (×) <$> (loadModule "prelude" primitives >>= loadModule "graphics")
       <@> successfulParse src program

openDatasetAs :: String -> Var -> Aff (Env 𝔹)
openDatasetAs file x = do
   ρ × s <- loadFile "fluid/dataset" file >>= parseWithDefaultImports
   let _ × v = successful (eval ρ =<< desugarFwd s)
   pure (Empty :+: x ↦ v)
