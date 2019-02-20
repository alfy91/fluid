import { __check, absurd } from "./util/Core"
import { ExternalObject, PersistentObject, Versioned, at, make, asVersioned } from "./util/Persistent"
import { Cons, List, Nil } from "./BaseTypes"
import { Bot, Env, EnvEntries, EnvEntry, ExtendEnv } from "./Env"
import { Expr } from "./Expr"
import { get, has } from "./FiniteMap"
import { BinaryOp, PrimResult, binaryOps } from "./Primitive"
import { Traced, Value, Value̊ } from "./Traced"

import App = Traced.App
import BinaryApp = Traced.BinaryApp
import BotKont = Expr.BotKont
import Empty = Traced.Empty
import Kont = Expr.Kont
import Let = Traced.Let
import LetRec = Traced.LetRec
import MatchAs = Traced.MatchAs
import RecDef = Expr.RecDef
import Trie = Expr.Trie
import UnaryApp = Traced.UnaryApp
import Var = Traced.Var
import VoidKont = Expr.VoidKont

type Tag = "expr" | "val" | "trace"

// The "runtime identity" of an expression. Always grounds out in an equivalent expression whose id is external.
export class EvalId<T extends Tag> implements PersistentObject {
   j: EnvEntries
   e: Versioned<Expr | RecDef>
   tag: T

   constructor_ (j: EnvEntries, e: Versioned<Expr | RecDef>, tag: T) {
      this.j = j
      // enforcing this invariant would require parameterising Expr by the type of its id:
      this.e = __check(e, it => it.__id instanceof ExternalObject)
      this.tag = tag
   }

   static make<T extends Tag> (j: EnvEntries, e: Versioned<Expr | RecDef>, tag: T): EvalId<T> {
      return make(EvalId, j, e, tag) as EvalId<T>
   }
}

export type ExprId = EvalId<"expr">
export type ValId = EvalId<"val">
export type TraceId = EvalId<"trace">

export module Eval {

// Note that an "eval id" is not a suitable memo-key for eval_: different demands will produce output environments of 
// different shapes. (For the same reason, eval_ is only monotone w.r.t. σ in the output environment if the ordering on
// tries implies equality of binding structure.) This effectively serves as an eval_ memo key in the meantime; probably
// want to subsume this into some memoisation infrastructure at some point.
class EvalKey<K extends Expr.Kont<K>> implements PersistentObject {
   j: EnvEntries
   e: Expr
   σ: Trie<K>

   constructor_ (j: EnvEntries, e: Expr, σ: Trie<K>) {
      this.j = j
      this.e = e
      this.σ = σ
   }

   static make<K extends Expr.Kont<K>> (j: EnvEntries, e: Expr, σ: Trie<K>): EvalKey<K> {
      return make(EvalKey, j, e, σ) as EvalKey<K>
   }
}
   
// Versioned so that we can access prior value of the environment when forward-slicing.
export class Result<K extends Kont<K>> implements PersistentObject {
   tv: Traced
   ρ: Env
   κ: K

   constructor_ (tv: Traced, ρ: Env, κ: K): void {
      this.tv = tv
      this.ρ = ρ
      this.κ = κ
   }

   static at<K extends Kont<K>> (α: PersistentObject, tv: Traced, ρ: Env, κ: K): Result<K> {
      return at(α, Result, tv, ρ, κ) as Result<K>
   }
}

export class Results<K extends Kont<K>> implements PersistentObject {
   tvs: List<Traced>
   ρ: Env
   κ: K

   constructor_ (tvs: List<Traced>, ρ: Env, κ: K): void {
      this.tvs = tvs
      this.ρ = ρ
      this.κ = κ
   }

   static make<K extends Kont<K>> (tvs: List<Traced>, ρ: Env, κ: K): Results<K> {
      return make(Results, tvs, ρ, κ) as Results<K>
   }
}

// Environments are snoc-lists, so this reverses declaration order, but semantically it's irrelevant.
export function closeDefs (δ_0: List<Expr.RecDef>, ρ: Env, δ: List<Expr.RecDef>): Env {
   if (Cons.is(δ)) {
      return ExtendEnv.make(closeDefs(δ_0, ρ, δ.tail), δ.head.x.str, EnvEntry.make(ρ, δ_0, δ.head.e))
   } else
   if (Nil.is(δ)) {
      return ρ
   } else {
      return absurd()
   }
}

// Parser ensures constructor patterns agree with constructor signatures.
function evalArgs<K extends Expr.Kont<K>> (ρ: Env, Π: Expr.Args<K>, es: List<Expr>): Results<K> {
   if (Cons.is(es)) {
      let σ: Trie<Expr.Args<K>>
      if (Expr.Args.Next.is(Π)) {
         σ = Π.σ
      } else
      if (Expr.Args.Top.is(Π)) {
         σ = Trie.Top.make(Expr.Args.Top.make(Π.κ))
      } else
      if (Expr.Args.Bot.is(Π)) {
         σ = Trie.Bot.make()
      } else {
         return absurd()
      }
      const {tv, ρ: ρʹ, κ: Πʹ}: Result<Expr.Args<K>> = eval_(ρ, es.head, σ),
            // propagate bot:
            {tvs, ρ: ρʺ, κ}: Results<K> = evalArgs(ρ, Πʹ instanceof Expr.BotKont ? Expr.Args.Bot.make() : Πʹ, es.tail)
      return Results.make(Cons.make(tv, tvs), Env.concat(ρʹ, ρʺ), κ)
   } else
   if (Nil.is(es)) {
      if (Expr.Args.End.is(Π) || Expr.Args.Top.is(Π)) {
         return Results.make(Nil.make(), Env.empty(), Π.κ)
      } else
      if (Expr.Args.Bot.is(Π)) {
         return Results.make(Nil.make(), Env.empty(), BotKont.make() as any) // ouch
      } else {
         return absurd()
      }
   } else {
      return absurd()
   }
}

export function eval_<K extends Expr.Kont<K>> (ρ: Env, e: Expr, σ: Trie<K>): Result<K> {
   const e_: Versioned<Expr> = asVersioned(e),
         k: TraceId = e_.__id as TraceId,
         kᵥ: ValId = EvalId.make(k.j, k.e, "val"),
         out: EvalKey<K> = EvalKey.make(k.j, k.e as Expr, σ)
   // An unevaluated expression has a bot trace for the sake of monotonicity across computations; might
   // want to reinstate the embedding of expressions into traces here.
   if (Trie.Bot.is(σ)) { 
      return Result.at(out, Traced.make(Traced.Bot.at(k), null), Bot.make(), BotKont.make() as any) // ouch
   } else
   if (Trie.Var.is(σ)) {
      const entry: EnvEntry = EnvEntry.make(ρ, Nil.make(), e)
      return Result.at(out, Traced.make(Traced.Bot.at(k), null), Env.singleton(σ.x.str, entry), σ.κ)
   } else
   if (e instanceof Expr.Bot) {
       // top demands "match" bottom; see issue #74
      return Result.at(out, Traced.make(Traced.Bot.at(k), null), Bot.make(), σ instanceof Trie.Top ? σ.κ : BotKont.make() as any) // ouch 
   } else
   if (e instanceof Expr.Constr) {
      let Π: Expr.Args<K>
      if (Trie.Constr.is(σ) && has(σ.cases, e.ctr.str)) {
         Π = get(σ.cases, e.ctr.str)!
      } else 
      if (Trie.Top.is(σ)) {
         Π = Expr.Args.Top.make(σ.κ)
      } else {
         return absurd("Demand mismatch.", e, σ)
      }
      const {tvs: args, ρ: ρʹ, κ}: Results<K> = evalArgs(ρ, Π, e.args)
      return Result.at(out, Traced.make(Empty.at(k), Value.Constr.at(kᵥ, e.ctr, args)), ρʹ, κ)
   } else
   if (e instanceof Expr.ConstInt && Trie.ConstInt.is(σ)) {
      return Result.at(out, Traced.make(Empty.at(k), Value.ConstInt.at(kᵥ, e.val)), Env.empty(), σ.κ)
   } else
   if (e instanceof Expr.ConstStr && Trie.ConstStr.is(σ)) {
      return Result.at(out, Traced.make(Empty.at(k), Value.ConstStr.at(kᵥ, e.val)), Env.empty(), σ.κ)
   } else
   if (e instanceof Expr.Fun && Trie.Fun.is(σ)) {
      return Result.at(out, Traced.make(Empty.at(k), Value.Closure2.at(kᵥ, ρ, e.σ)), Env.empty(), σ.κ)
   } else
   if (e instanceof Expr.PrimOp && Trie.Fun.is(σ)) {
      return Result.at(out, Traced.make(Empty.at(k), Value.PrimOp.at(kᵥ, e.op)), Env.empty(), σ.κ)
   } else
   if (e instanceof Expr.Var) {
      const x: string = e.x.str
      if (ρ.has(x)) { 
         const {ρ: ρʹ, δ, e: eʹ}: EnvEntry = ρ.get(x)!,
               {tv, ρ: ρʺ, κ}: Result<K> = eval_(closeDefs(δ, ρʹ, δ), eʹ, σ)
         return Result.at(out, Traced.make(Var.at(k, e.x, tv.t), tv.v), ρʺ, κ)
      } else {
         return absurd("Variable not found.", x)
      }
   } else
   if (e instanceof Expr.App) {
      const {tv: tf}: Result<VoidKont> = eval_(ρ, e.func, Trie.Fun.make(Expr.VoidKont.make())),
            f: Value̊ = tf.v
      if (f instanceof Value.Closure2) {
         const {tv: tu, ρ: ρʹ, κ: eʹ}: Result<Expr> = eval_(ρ, e.arg, f.σ),
               {tv, ρ: ρʺ, κ}: Result<K> = eval_(Env.concat(f.ρ, ρʹ), eʹ, σ)
         return Result.at(out, Traced.make(App.at(k, tf, tu, tv.t), tv.v), ρʺ, κ)
      } else
      // Primitives with identifiers as names are unary and first-class.
      if (f instanceof Value.PrimOp) {
         const {tv: tu}: Result<VoidKont> = eval_(ρ, e.arg, f.op.σ),
               [v, κ]: PrimResult<K> = f.op.b.invoke(tu.v!, σ)(kᵥ)
         return Result.at(out, Traced.make(UnaryApp.at(k, tf, tu), v), Env.empty(), κ)
      } else {
         return absurd()
      }
   } else
   if (e instanceof Expr.Let) {
      const {tv: tu, ρ: ρʹ, κ: eʹ}: Result<Expr> = eval_(ρ, e.e, e.σ),
            {tv, ρ: ρʺ, κ}: Result<K> = eval_(Env.concat(ρ, ρʹ), eʹ, σ)
      return Result.at(out, Traced.make(Let.at(k, tu, Trie.Var.make(e.σ.x, tv.t)), tv.v), ρʺ, κ)
   } else
   if (e instanceof Expr.LetRec) {
      const ρʹ: Env = closeDefs(e.δ, ρ, e.δ),
            {tv, ρ: ρʺ, κ}: Result<K> = eval_(ρʹ, e.e, σ)
      return Result.at(out, Traced.make(LetRec.at(k, e.δ, tv), tv.v), ρʺ, κ)
   } else
   if (e instanceof Expr.MatchAs) {
      const {tv: tu, ρ: ρʹ, κ: eʹ}: Result<Expr> = eval_(ρ, e.e, e.σ),
            {tv, ρ: ρʺ, κ}: Result<K> = eval_(Env.concat(ρ, ρʹ), eʹ, σ)
      return Result.at(out, Traced.make(MatchAs.at(k, tu, e.σ, tv.t), tv.v), ρʺ, κ)
   } else
   // Operators (currently all binary) are "syntax", rather than names.
   if (e instanceof Expr.BinaryApp) {
      if (binaryOps.has(e.opName.str)) {
         const op: BinaryOp = binaryOps.get(e.opName.str)!,
               {tv: tv1}: Result<VoidKont> = eval_(ρ, e.e1, op.σ1),
               {tv: tv2}: Result<VoidKont> = eval_(ρ, e.e2, op.σ2),
               [v, κ]: PrimResult<K> = op.b.invoke(tv1.v!, tv2.v!, σ)(kᵥ)
         return Result.at(out, Traced.make(BinaryApp.at(k, tv1, e.opName, tv2), v), Env.empty(), κ)
      } else {
         return absurd("Operator name not found.", e.opName)
      }
   } else {
      return absurd("Unimplemented expression form.", e)
   }
}

}
