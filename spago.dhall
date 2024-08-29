{-
Welcome to a Spago project!
You can edit this file as you like.
-}
{ name = ""
, dependencies =
  [ "aff"
  , "aff-promise"
  , "affjax"
  , "affjax-web"
  , "arrays"
  , "bifunctors"
  , "console"
  , "control"
  , "debug"
  , "effect"
  , "either"
  , "exceptions"
  , "exists"
  , "filterable"
  , "foldable-traversable"
  , "foreign-object"
  , "functors"
  , "graphs"
  , "http-methods"
  , "identity"
  , "integers"
  , "lists"
  , "maybe"
  , "newtype"
  , "nonempty"
  , "numbers"
  , "ordered-collections"
  , "parsing"
  , "partial"
  , "prelude"
  , "profunctor"
  , "st"
  , "strings"
  , "tailrec"
  , "toppokki"
  , "transformers"
  , "tuples"
  , "unfoldable"
  , "unicode"
  , "unsafe-coerce"
  , "web-events"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs", "test/**/*.purs" ]
, backend = "purs-backend-es build"
}