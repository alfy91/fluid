module Parse2 where

import Prelude hiding (absurd, add, between, join)

import Bindings (Bind, Var, (↦))
import Control.Alt ((<|>))
import Control.Apply (lift2)
import Control.Lazy (fix)
import Control.MonadPlus (empty)
import Data.Array (cons, elem, fromFoldable)
import Data.Either (choose)
import Data.Function (on)
import Data.Identity (Identity)
import Data.List (List(..), (:), concat, foldr, groupBy, singleton, snoc, sortBy)
import Data.List.NonEmpty (NonEmptyList(..), toList)
import Data.Map (values)
import Data.NonEmpty ((:|))
import Data.Ordering (invert)
import Data.Profunctor.Choice ((|||))
import DataType (Ctr, cPair, isCtrName, isCtrOp)
import Expr2 (Expr(..)) as E
import Expr2 (class Desugarable, mustDesug)
import Lattice2 (Raw)
import Parsing.Combinators (between, sepBy, sepBy1, try)
import Parsing.Expr (Assoc(..), Operator(..), OperatorTable, buildExprParser)
import Parsing.Language (emptyDef)
import Parsing.String (char, eof)
import Parsing.String.Basic (oneOf)
import Parsing.Token (GenLanguageDef(..), LanguageDef, TokenParser, alphaNum, letter, makeTokenParser, unGenLanguageDef)
import Primitive.Parse (OpDef, opDefs)
import SExpr2 (Branch(..), Branches(..), Clause, SExpr(..), ListRest(..), ListRestPattern(..), Module(..), Pattern(..), Qualifier(..), RecDefs, VarDef(..), VarDefs)
import Util (Endo, type (×), (×), type (+), error, onlyIf)
import Util.Pair (Pair(..))
import Util.Parse (SParser, sepBy_try, sepBy1_try, some)

-- Constants (should also be used by prettyprinter). Haven't found a way to avoid the type definition.
str
   :: { arrayLBracket :: String
      , arrayRBracket :: String
      , as :: String
      , backslash :: String
      , backtick :: String
      , bar :: String
      , colon :: String
      , colonEq :: String
      , dictLBracket :: String
      , dictRBracket :: String
      , dot :: String
      , ellipsis :: String
      , else_ :: String
      , equals :: String
      , fun :: String
      , if_ :: String
      , in_ :: String
      , lArrow :: String
      , lBracket :: String
      , let_ :: String
      , match :: String
      , rArrow :: String
      , rBracket :: String
      , then_ :: String
      }

str =
   { arrayLBracket: "[|"
   , arrayRBracket: "|]"
   , as: "as"
   , backslash: "\\"
   , backtick: "`"
   , bar: "|"
   , colon: ":"
   , colonEq: ":="
   , dictLBracket: "{|"
   , dictRBracket: "|}"
   , dot: "."
   , ellipsis: ".."
   , else_: "else"
   , equals: "="
   , fun: "fun"
   , if_: "if"
   , in_: "in"
   , lArrow: "<-"
   , lBracket: "["
   , let_: "let"
   , match: "match"
   , rArrow: "->"
   , rBracket: "]"
   , then_: "then"
   }

languageDef :: LanguageDef
languageDef = LanguageDef (unGenLanguageDef emptyDef)
   { commentStart = "{-"
   , commentEnd = "-}"
   , commentLine = "--"
   , nestedComments = true
   , identStart = letter <|> char '_'
   , identLetter = alphaNum <|> oneOf [ '_', '\'' ]
   , opStart = opChar
   , opLetter = opChar
   , reservedOpNames = [ str.bar, str.ellipsis, str.equals, str.lArrow, str.rArrow ]
   , reservedNames = [ str.as, str.else_, str.fun, str.if_, str.in_, str.let_, str.match, str.then_ ]
   , caseSensitive = true
   }
   where
   opChar :: SParser Char
   opChar = oneOf
      [ ':'
      , '!'
      , '#'
      , '$'
      , '%'
      , '&'
      , '*'
      , '+'
      , '.'
      , '/'
      , '<'
      , '='
      , '>'
      , '?'
      , '@'
      , '\\'
      , '^'
      , '|'
      , '-'
      , '~'
      ]

token :: TokenParser
token = makeTokenParser languageDef

lArrow :: SParser Unit
lArrow = token.reservedOp str.lArrow

lBracket :: SParser Unit
lBracket = void (token.symbol str.lBracket)

backtick :: SParser Unit
backtick = void (token.symbol str.backtick)

bar :: SParser Unit
bar = token.reservedOp str.bar

colonEq :: SParser Unit
colonEq = token.reservedOp str.colonEq

ellipsis :: SParser Unit
ellipsis = token.reservedOp str.ellipsis

equals :: SParser Unit
equals = token.reservedOp str.equals

rBracket :: SParser Unit
rBracket = void $ token.symbol str.rBracket

rArrow :: SParser Unit
rArrow = token.reservedOp str.rArrow

-- 'reserved' parser only checks that str isn't a prefix of a valid identifier, not that it's in reservedNames.
keyword ∷ String → SParser Unit
keyword str' =
   if str' `elem` (unGenLanguageDef languageDef).reservedNames then token.reserved str'
   else error $ str' <> " is not a reserved word"

sugarH :: forall s e. Desugarable s e => SParser (Raw s) -> SParser (Raw e)
sugarH sugP = mustDesug <$> sugP

ident ∷ SParser Var
ident = do
   x <- token.identifier
   onlyIf (not $ isCtrName x) x

ctr :: SParser Ctr
ctr = do
   x <- token.identifier
   onlyIf (isCtrName x) x

field :: forall a. SParser a -> SParser (Bind a)
field p = ident `lift2 (↦)` (token.colon *> p)

simplePattern :: Endo (SParser Pattern)
simplePattern pattern' =
   try listEmpty
      <|> listNonEmpty
      <|> try constr
      <|> try record
      <|> try var
      <|> try (token.parens pattern')
      <|> pair

   where
   listEmpty :: SParser Pattern
   listEmpty = token.brackets $ pure $ PListEmpty

   listNonEmpty :: SParser Pattern
   listNonEmpty = lBracket *> (PListNonEmpty <$> pattern' <*> fix listRest)
      where
      listRest :: Endo (SParser ListRestPattern)
      listRest listRest' =
         rBracket *> pure PEnd <|>
            token.comma *> (PNext <$> pattern' <*> listRest')

   -- Constructor name as a nullary constructor pattern.
   constr :: SParser Pattern
   constr = PConstr <$> ctr <@> Nil

   record :: SParser Pattern
   record = sepBy (field pattern') token.comma <#> PRecord # token.braces

   -- TODO: anonymous variables
   var :: SParser Pattern
   var = PVar <$> ident

   pair :: SParser Pattern
   pair =
      token.parens $ do
         π <- pattern' <* token.comma
         π' <- pattern'
         pure $ PConstr cPair (π : π' : Nil)

patternDelim :: SParser Unit
patternDelim = rArrow <|> equals

-- "curried" controls whether nested functions are permitted in this context
branch :: Boolean -> SParser (Raw E.Expr) -> SParser Unit -> SParser (Raw Branch)
branch curried expr' delim = do
   πs <-
      if curried then some $ simplePattern pattern
      else NonEmptyList <$> pattern `lift2 (:|)` pure Nil
   e <- delim *> expr'
   pure $ Branch (πs × e)

branch_curried :: SParser (Raw E.Expr) -> SParser Unit -> SParser (Raw Branch)
branch_curried expr' delim =
   Branch <$> some (simplePattern pattern) `lift2 (×)` (delim *> expr')

branch_uncurried :: SParser (Raw E.Expr) -> SParser Unit -> SParser (Pattern × Raw E.Expr)
branch_uncurried expr' delim =
   pattern `lift2 (×)` (delim *> expr')

branchMany
   :: forall b
    . SParser (Raw E.Expr)
   -> (SParser (Raw E.Expr) -> SParser Unit -> SParser b)
   -> SParser (NonEmptyList b)
branchMany expr' branch_ = token.braces $ sepBy1 (branch_ expr' rArrow) token.semi

branches :: forall b. SParser (Raw E.Expr) -> (SParser (Raw E.Expr) -> SParser Unit -> SParser b) -> SParser (NonEmptyList b)
branches expr' branch_ =
   (pure <$> branch_ expr' patternDelim) <|> branchMany expr' branch_

varDefs :: SParser (Raw E.Expr) -> SParser (Raw VarDefs)
varDefs expr' = keyword str.let_ *> sepBy1_try clause token.semi
   where
   clause :: SParser (Raw VarDef)
   clause = VarDef <$> (pattern <* equals) <*> expr'

recDefs :: SParser (Raw E.Expr) -> SParser (Raw RecDefs)
recDefs expr' = do
   keyword str.let_ *> sepBy1_try clause token.semi
   where
   clause :: SParser (Raw Clause)
   clause = ident `lift2 (×)` (branch_curried expr' equals)

defs :: SParser (Raw E.Expr) -> SParser (List (Raw VarDefs + Raw RecDefs))
defs expr' = singleton <$> choose (try $ varDefs expr') (recDefs expr')

-- Tree whose branches are binary primitives and whose leaves are application chains.
expr_ :: SParser (Raw E.Expr)
expr_ = fix $ appChain >>> buildExprParser ([ backtickOp ] `cons` operators binaryOp)
   where
   -- Pushing this to front of operator table to give it higher precedence than any other binary op.
   -- (Reasonable approximation to Haskell, where backticked functions have default precedence 9.)
   backtickOp :: Operator Identity String (Raw E.Expr)
   backtickOp = flip Infix AssocLeft $ do
      x <- between backtick backtick ident
      pure (\e e' -> mustDesug $ BinaryApp e x e')

   -- Syntactically distinguishing infix constructors from other operators (a la Haskell) allows us to
   -- optimise an application tree into a (potentially partial) constructor application. We also treat
   -- record lookup syntactically like a binary operator, although the second argument must always be a
   -- variable.
   binaryOp :: String -> SParser (Raw E.Expr -> Raw E.Expr -> Raw E.Expr)
   binaryOp op = do
      op' <- token.operator
      onlyIf (op == op') $
         if op == str.dot then \e e' -> case e' of
            E.Var x -> E.Project e x
            _ -> error "Field names are not first class."
         else if isCtrOp op' then \e e' -> E.Constr unit op' (e : e' : empty)
         else \e e' -> mustDesug $ BinaryApp e op e'

   -- Left-associative tree of applications of one or more simple terms.
   appChain :: Endo (SParser (Raw E.Expr))
   appChain expr' = simpleExpr >>= rest
      where
      rest :: Raw E.Expr -> SParser (Raw E.Expr)
      rest e@(E.Constr α c es) = ctrArgs <|> pure e
         where
         ctrArgs :: SParser (Raw E.Expr)
         ctrArgs = simpleExpr >>= \e' -> rest (E.Constr α c (es <> (e' : empty)))
      rest e = ((E.App e <$> simpleExpr) >>= rest) <|> pure e

      -- Any expression other than an operator tree or an application chain.
      simpleExpr :: SParser (Raw E.Expr)
      simpleExpr =
         -- matrix before list
         matrix
            <|> try nil
            <|> listNonEmpty
            <|> listComp
            <|> listEnum
            <|> try constr
            <|> dict
            <|> record
            <|> try variable
            <|> try float
            <|> try int -- int may start with +/-
            <|> string
            <|> defsExpr
            <|> matchAs
            <|> try (token.parens expr')
            <|> try parensOp
            <|> pair
            <|> lambda
            <|> ifElse

         where
         matrix :: SParser (Raw E.Expr)
         matrix =
            between (token.symbol str.arrayLBracket) (token.symbol str.arrayRBracket) $
               E.Matrix unit
                  <$> (expr' <* bar)
                  <*> token.parens (ident `lift2 (×)` (token.comma *> ident))
                  <*> (keyword str.in_ *> expr')

         nil :: SParser (Raw E.Expr)
         nil = sugarH $ token.brackets $ pure (ListEmpty unit)

         listNonEmpty :: SParser (Raw E.Expr)
         listNonEmpty =
            sugarH $ lBracket *> (ListNonEmpty unit <$> expr' <*> fix listRest)

            where
            listRest :: Endo (SParser (Raw ListRest))
            listRest listRest' =
               rBracket *> pure (End unit) <|>
                  token.comma *> (Next unit <$> expr' <*> listRest')

         listComp :: SParser (Raw E.Expr)
         listComp = sugarH $ token.brackets $
            pure (ListComp unit) <*> expr' <* bar <*> sepBy1 qualifier token.comma

            where
            qualifier :: SParser (Raw Qualifier)
            qualifier =
               Generator <$> pattern <* lArrow <*> expr'
                  <|> Declaration <$> (VarDef <$> (keyword str.let_ *> pattern <* equals) <*> expr')
                  <|> Guard <$> expr'

         listEnum :: SParser (Raw E.Expr)
         listEnum = sugarH $ token.brackets $
            pure ListEnum <*> expr' <* ellipsis <*> expr'

         constr :: SParser (Raw E.Expr)
         constr = E.Constr unit <$> ctr <@> empty

         dict :: SParser (Raw E.Expr)
         dict = sepBy (Pair <$> (expr' <* colonEq) <*> expr') token.comma <#> E.Dictionary unit #
            between (token.symbol str.dictLBracket) (token.symbol str.dictRBracket)

         record :: SParser (Raw E.Expr)
         record = sugarH $ sepBy (field expr') token.comma <#> Record unit # token.braces

         variable :: SParser (Raw E.Expr)
         variable = ident <#> E.Var

         signOpt :: ∀ a. Ring a => SParser (a -> a)
         signOpt = (char '-' $> negate) <|> (char '+' $> identity) <|> pure identity

         -- built-in integer/float parsers don't seem to allow leading signs.
         int :: SParser (Raw E.Expr)
         int = do
            sign <- signOpt
            (sign >>> E.Int unit) <$> token.natural

         float :: SParser (Raw E.Expr)
         float = do
            sign <- signOpt
            (sign >>> E.Float unit) <$> token.float

         string :: SParser (Raw E.Expr)
         string = E.Str unit <$> token.stringLiteral

         defsExpr :: SParser (Raw E.Expr)
         defsExpr = do
            defs' <- concat <<< toList <$> sepBy1 (defs expr') token.semi
            foldr (\def -> mustDesug <<< (Let ||| LetRec) def) <$> (keyword str.in_ *> expr') <@> defs'

         matchAs :: SParser (Raw E.Expr)
         matchAs =
            sugarH $ MatchAs <$> (keyword str.match *> expr' <* keyword str.as) <*> branches expr' branch_uncurried

         -- any binary operator, in parentheses
         parensOp :: SParser (Raw E.Expr)
         parensOp = E.Op <$> token.parens token.operator

         pair :: SParser (Raw E.Expr)
         pair = token.parens $
            (pure $ \e e' -> E.Constr unit cPair (e : e' : empty)) <*> (expr' <* token.comma) <*> expr'

         lambda :: SParser (Raw E.Expr)
         lambda = E.Lambda <$> (sugarH $ Branches <$> (keyword str.fun *> (branches expr' branch_curried)))

         ifElse :: SParser (Raw E.Expr)
         ifElse = sugarH $ pure IfElse
            <*> (keyword str.if_ *> expr')
            <* keyword str.then_
            <*> expr'
            <* keyword str.else_
            <*> expr'

-- each element of the top-level list opDefs corresponds to a precedence level
operators :: forall a. (String -> SParser (a -> a -> a)) -> OperatorTable Identity String a
operators binaryOp =
   fromFoldable $
      fromFoldable <$>
         ops <#> (<$>) (\({ op, assoc }) -> Infix (try (binaryOp op)) assoc)
   where
   ops :: List (NonEmptyList OpDef)
   ops = groupBy (eq `on` _.prec) (sortBy (\x -> comparing _.prec x >>> invert) (values opDefs))

-- Pattern with no continuation.
pattern :: SParser Pattern
pattern = fix $ appChain_pattern >>> buildExprParser (operators infixCtr)
   where
   -- Analogous in some way to app_chain, but nothing higher-order here: no explicit application nodes,
   -- non-saturated constructor applications, or patterns other than constructors in the function position.
   appChain_pattern :: Endo (SParser Pattern)
   appChain_pattern pattern' = simplePattern pattern' >>= rest
      where
      rest ∷ Pattern -> SParser Pattern
      rest π@(PConstr c πs) = ctrArgs <|> pure π
         where
         ctrArgs :: SParser Pattern
         ctrArgs = simplePattern pattern' >>= \π' -> rest $ PConstr c (πs `snoc` π')
      rest π = pure π

   infixCtr :: String -> SParser (Pattern -> Pattern -> Pattern)
   infixCtr op = do
      op' <- token.operator
      onlyIf (isCtrOp op' && op == op') \π π' -> PConstr op' (π : π' : Nil)

topLevel :: forall a. Endo (SParser a)
topLevel p = token.whiteSpace *> p <* eof

program ∷ SParser (Raw E.Expr)
program = topLevel expr_

module_ :: SParser (Raw Module)
module_ = Module <<< concat <$> topLevel (sepBy_try (defs expr_) token.semi <* token.semi)
