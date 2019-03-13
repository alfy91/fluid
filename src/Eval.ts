import { absurd, as, assert } from "./util/Core"
import { PersistentObject, Versioned, make, asVersioned } from "./util/Persistent"
import { ann, bot } from "./Annotated"
import { Cons, List, Nil } from "./BaseTypes"
import { Env, EmptyEnv, ExtendEnv } from "./Env"
import { ExplVal, Match, Value } from "./ExplVal"
import { Expr } from "./Expr"
import { instantiate } from "./Instantiate"
import { match, matchVar, unmatch } from "./Match"
import { BinaryOp, binaryOps } from "./Primitive"

import App = ExplVal.App
import BinaryApp = ExplVal.BinaryApp
import Empty = ExplVal.Empty
import Fun = Expr.Fun
import Let = ExplVal.Let
import LetRec = ExplVal.LetRec
import MatchAs = ExplVal.MatchAs
import RecDef = Expr.RecDef
import Trie = Expr.Trie
import UnaryApp = ExplVal.UnaryApp
import Var = ExplVal.Var

type Tag = "val" | "expl"

// The "runtime identity" of an expression. In the formalism we use a "flat" representation so that e always has an external id;
// here it is more convenient to use an isomorphic nested format.
export class ExprId implements PersistentObject {
   j: List<Value>
   e: Versioned<Expr | RecDef>

   constructor_ (j: List<Value>, e: Versioned<Expr | RecDef>) {
      this.j = j
      this.e = e
   }

   static make<T extends Tag> (j: List<Value>, e: Versioned<Expr | RecDef>): ExprId {
      return make(ExprId, j, e)
   }
}

export class Tagged<T extends Tag> implements PersistentObject {
   e: Expr
   tag: T

   constructor_ (e: Expr, tag: T) {
      this.e = e
      this.tag = tag
   }

   static make<T extends Tag> (e: Expr, tag: T): Tagged<T> {
      return make(Tagged, e, tag) as Tagged<T>
   }
}

// User-level error.
export function error (msg: string, ...xs: any[]): any {
   if (xs.length > 0) {
      console.warn("Error data:\n")
      xs.forEach(x => console.warn(x))
   }
   throw new Error("User error")
}

export type ValId = Tagged<"val">
export type ExplId = Tagged<"expl">

export module Eval {

// Environments are snoc-lists, so this reverses declaration order, but semantically it's irrelevant.
export function closeDefs (δ_0: List<Expr.RecDef>, ρ: Env, δ: List<Expr.RecDef>): Env {
   if (Cons.is(δ)) {
      const f: Fun = δ.head.f,
            kᵥ: ValId = Tagged.make(f, "val")
      return ExtendEnv.make(closeDefs(δ_0, ρ, δ.tail), δ.head.x.str, Value.Closure.at(kᵥ, f.α, ρ, δ_0, f.σ))
   } else
   if (Nil.is(δ)) {
      return EmptyEnv.make()
   } else {
      return absurd()
   }
}

// ρ is a collection of one or more closures. Note that the required joins have already been computed.
export function uncloseDefs (ρ: Env): [Env, List<Expr.RecDef>] {
   const fs: List<Value.Closure> = ρ.entries().map(v => as(v, Value.Closure))
   if (Cons.is(fs)) {
      return [fs.head.ρ, fs.head.δ]
   } else {
      return absurd()
   }
}

export function eval_ (ρ: Env, e: Expr): ExplVal {
   const k: ExplId = Tagged.make(e, "expl"),
         kᵥ: ValId = Tagged.make(e, "val")
   if (e instanceof Expr.ConstInt) {
      return ExplVal.make(ρ, Empty.at(k), Value.ConstInt.at(kᵥ, e.α, e.val))
   } else
   if (e instanceof Expr.ConstStr) {
      return ExplVal.make(ρ, Empty.at(k), Value.ConstStr.at(kᵥ, e.α, e.val))
   } else
   if (e instanceof Expr.Fun) {
      return ExplVal.make(ρ, Empty.at(k), Value.Closure.at(kᵥ, e.α, ρ, Nil.make(), e.σ))
   } else
   if (e instanceof Expr.PrimOp) {
      return ExplVal.make(ρ, Empty.at(k), Value.PrimOp.at(kᵥ, e.α, e.op))
   } else
   if (e instanceof Expr.Constr) {
      return ExplVal.make(ρ, Empty.at(k), Value.Constr.at(kᵥ, e.α, e.ctr, e.args.map(e => eval_(ρ, e))))
   } else
   if (e instanceof Expr.Var) {
      const x: string = e.x.str
      if (ρ.has(x)) { 
         const v: Value = ρ.get(x)!
         return ExplVal.make(ρ, Var.at(k, e.x), v.copyAt(kᵥ, ann.meet(v.α, e.α)))
      } else {
         return error("Variable not found.", x)
      }
   } else
   if (e instanceof Expr.App) {
      const tf: ExplVal = eval_(ρ, e.func),
            f: Value = tf.v
      if (f instanceof Value.Closure) {
         const tu: ExplVal = eval_(ρ, e.arg),
               [ρʹ, {ξ, κ: eʹ}, α] = match(tu.v, f.σ),
               ρ_defs: Env = closeDefs(f.δ, f.ρ, f.δ),
               tv: ExplVal = eval_(Env.concat(Env.concat(f.ρ, ρ_defs), ρʹ), instantiate(ρʹ, eʹ))
         return ExplVal.make(ρ, App.at(k, tf, tu, ρʹ, ρ_defs, Match.Plug.make(ξ, tv)), tv.v.copyAt(kᵥ, ann.meet(f.α, α, tv.v.α, e.α)))
      } else
      // Primitives with identifiers as names are unary and first-class.
      if (f instanceof Value.PrimOp) {
         const tu: ExplVal = eval_(ρ, e.arg)
         return ExplVal.make(ρ, UnaryApp.at(k, tf, tu), f.op.b.op(tu.v!)(kᵥ, ann.meet(f.α, tu.v.α, e.α)))
      } else {
         return absurd()
      }
   } else
   // Operators (currently all binary) are "syntax", rather than names.
   if (e instanceof Expr.BinaryApp) {
      if (binaryOps.has(e.opName.str)) {
         const op: BinaryOp = binaryOps.get(e.opName.str)!, // opName lacks annotations
               [tv1, tv2]: [ExplVal, ExplVal] = [eval_(ρ, e.e1), eval_(ρ, e.e2)],
               v: Value = op.b.op(tv1.v!, tv2.v!)(kᵥ, ann.meet(tv1.v.α, tv2.v.α, e.α))
         return ExplVal.make(ρ, BinaryApp.at(k, tv1, e.opName, tv2), v)
      } else {
         return error("Operator name not found.", e.opName)
      }
   } else
   if (e instanceof Expr.Let) {
      const tu: ExplVal = eval_(ρ, e.e),
            [ρʹ, {ξ, κ: eʹ}, α] = matchVar<Expr>(tu.v, e.σ),
            tv: ExplVal = eval_(Env.concat(ρ, ρʹ), instantiate(ρʹ, eʹ))
      return ExplVal.make(ρ, Let.at(k, tu, Match.Plug.make(ξ, tv)), tv.v.copyAt(kᵥ, ann.meet(α, tv.v.α, e.α)))
   } else
   if (e instanceof Expr.LetRec) {
      const ρʹ: Env = closeDefs(e.δ, ρ, e.δ),
            tv: ExplVal = eval_(Env.concat(ρ, ρʹ), instantiate(ρʹ, e.e))
      return ExplVal.make(ρ, LetRec.at(k, e.δ, ρʹ, tv), tv.v.copyAt(kᵥ, ann.meet(tv.v.α, e.α)))
   } else
   if (e instanceof Expr.MatchAs) {
      const tu: ExplVal = eval_(ρ, e.e),
            [ρʹ, {ξ, κ: eʹ}, α] = match(tu.v, e.σ),
            tv: ExplVal = eval_(Env.concat(ρ, ρʹ), instantiate(ρʹ, eʹ))
      return ExplVal.make(ρ, MatchAs.at(k, tu, ρʹ, Match.Plug.make(ξ, tv)), tv.v.copyAt(kᵥ, ann.meet(α, tv.v.α, e.α)))
   } else {
      return absurd("Unimplemented expression form.", e)
   }
}

// Output environment is written to.
export function uneval ({ρ, t, v}: ExplVal): Expr {
   const kᵥ: ValId = asVersioned(v).__id as ValId,
         k: ExprId = asVersioned(kᵥ.e).__id as ExprId
   if (t instanceof Empty) {
      if (v instanceof Value.ConstInt) {
         bot(ρ)
         return Expr.ConstInt.at(k, v.α, v.val)
      } else
      if (v instanceof Value.ConstStr) {
         bot(ρ)
         return Expr.ConstStr.at(k, v.α, v.val)
      } else
      if (v instanceof Value.Closure) {
         assert(v.δ.length === 0)
         bot(ρ)
         return Expr.Fun.at(k, v.α, v.σ)
      } else 
      if (v instanceof Value.PrimOp) {
         bot(ρ)
         return Expr.PrimOp.at(k, v.α, v.op)
      } else
      if (v instanceof Value.Constr) {
         // reverse order but shouldn't matter in absence of side-effects:
         return Expr.Constr.at(k, v.α, v.ctr, v.args.map(uneval))
      } else {
         return absurd()
      }
   } else
   if (t instanceof Var) {
      const x: string = t.x.str
      bot(ρ)
      assert(ρ.has(x))
         ρ.get(x)!.setα(v.α)
         return Expr.Var.at(k, v.α, t.x)
   }
   else
   if (t instanceof App) {
      const f: Value.Closure | Value.PrimOp = t.func.v as (Value.Closure | Value.PrimOp)
      if (f instanceof Value.Closure) {
         const {ξ, κ: tv} = t.ξtv
         tv.v.setα(v.α)
         unmatch(t.ρ_match, Match.Plug.make(ξ, uneval(tv)), v.α)
         uncloseDefs(t.ρ_defs)
         f.setα(v.α)
         return Expr.App.at(k, v.α, uneval(t.func), uneval(t.arg))
      } else
      if (f instanceof Value.PrimOp) {
         return Expr.App.at(k, v.α, uneval(t.func).setα(v.α), uneval(t.arg).setα(v.α))
      } else {
         return absurd()
      }
   } else
   if (t instanceof BinaryApp) {
      assert(binaryOps.has(t.opName.str))
      t.tv1.v.setα(v.α)
      t.tv2.v.setα(v.α)
      return Expr.BinaryApp.at(k, v.α, uneval(t.tv1), t.opName, uneval(t.tv2))
   } else
   if (t instanceof Let) {
      const {ξ, κ: tv} = t.ξtv
      tv.v.setα(v.α)
      const eʹ: Expr = uneval(tv),
            e: Expr = uneval(t.tu) // unmatch not required - suffices to uneval in reverse order
      return Expr.Let.at(k, v.α, e, Trie.Var.make(ξ.x, eʹ))
   } else
   if (t instanceof LetRec) {
      t.tv.v.setα(v.α)
      const e: Expr = uneval(t.tv),
            [, δ]: [Env, List<RecDef>] = uncloseDefs(t.ρ_defs)
      return Expr.LetRec.at(k, v.α, δ, e)
   } else
   if (t instanceof MatchAs) {
      const {ξ, κ: tv} = t.ξtv
      tv.v.setα(v.α)
      const [, σ] = unmatch(t.ρ_match, Match.Plug.make(ξ, uneval(tv)), v.α)
      return Expr.MatchAs.at(k, v.α, uneval(t.tu), σ)
   } else {
      return absurd()
   }
}

}
