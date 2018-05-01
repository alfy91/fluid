import { __check, assert, make } from "./util/Core"
import { JoinSemilattice, eq } from "./util/Ord"
import { Lexeme } from "./util/parse/Core"
import { List } from "./BaseTypes"
import { Env } from "./Env"
import { FiniteMap, unionWith } from "./FiniteMap"
import { Runtime } from "./Eval"
import { UnaryOp } from "./Primitive"
import { ExternalObject, VersionedObject, PersistentObject, create } from "./Runtime"

// Constants used for parsing, and also for toString() implementations.
export namespace str {
   export const arrow: string = "→"
   export const as: string = "as"
   export const equals: string = "="
   export const fun: string = "fun"
   export const in_: string = "in"
   export const let_: string = "let"
   export const letRec: string = "letrec"
   export const match: string = "match"
   export const parenL: string = "("
   export const parenR: string = ")"
   export const quotes: string = '"'
}

export namespace Lex {
   export class Ctr extends Lexeme {
      constructor(str: string) {
         super(str)
      }

      __Ctr(): void {
         // discriminator
      }
   }

   export class IntLiteral extends Lexeme {
      constructor(str: string) {
         super(str)
      }

      toNumber(): number {
         return parseInt(this.str)
      }
   }

   export class Keyword extends Lexeme {
      constructor(str: string) {
         super(str)
      }
   }

   // The name of a primitive operation, such as * or +, where that name is /not/ a standard identifier.
   // Other uses of primitive operations are treated as variables.
   export class OpName extends Lexeme {
      constructor(str: string) {
         super(str)
      }

      __OpName(): void {
         // discriminator
      }
   }

   export class StringLiteral extends Lexeme {
      constructor(str: string) {
         super(str)
      }

      toString(): string {
         return str.quotes + this.str + str.quotes
      }
   }

   export class Var extends Lexeme {
      constructor(str: string) {
         super(str)
      }

      __Var(): void {
         // discriminator
      }
   }
}

export type Value = Value.Value

export namespace Value {
   export class Value extends VersionedObject {
      __Value(): void {
         // discriminator
      }
   }

   export class Closure extends Value {
      ρ: Env
      σ: Trie
   
      static at (α: PersistentObject, ρ: Env, σ: Trie): Closure {
         const this_: Closure = create(α, Closure)
         this_.ρ = ρ
         this_.σ = σ
         this_.__version()
         return this_
      }
   }

   export class Prim extends Value {
      __Prim(): void {
         // discriminator
      }
   }
   
   export class ConstInt extends Prim {
      val: number
   
      static at (α: PersistentObject, val: number): ConstInt {
         const this_: ConstInt = create(α, ConstInt)
         this_.val = val
         this_.__version()
         return this_
      }

      toString (): string {
         return `${this.val}`
      }
   }
   
   export class ConstStr extends Prim {
      val: string
   
      static at (α: PersistentObject, val: string): ConstStr {
         const this_: ConstStr = create(α, ConstStr)
         this_.val = val
         this_.__version()
         return this_
      }

      toString (): string {
         return `"${this.val}"`
      }
   }
   
   export class Constr extends Value {
      ctr: Lex.Ctr
      args: List<Traced>
   
      static at (α: PersistentObject, ctr: Lex.Ctr, args: List<Traced>): Constr {
         const this_: Constr = create(α, Constr)
         this_.ctr = ctr
         this_.args = args
         this_.__version()
         return this_
      }
   }

   export class PrimOp extends Value {
      op: UnaryOp
   
      static at (α: PersistentObject, op: UnaryOp): PrimOp {
         const this_: PrimOp = create(α, PrimOp)
         this_.op = op
         this_.__version()
         return this_
      }
   }
}

export type Expr = Expr.Expr

export namespace Expr {
   export class Expr extends VersionedObject<ExternalObject> {
      __Expr(): void {
         // discriminator
      }
   }

   export class App extends Expr {
      func: Expr
      arg: Expr

      static at (i: ExternalObject, func: Expr, arg: Expr): App {
         const this_: App = create(i, App)
         this_.func = func
         this_.arg = arg
         this_.__version()
         return this_
      }
   }

   export class ConstInt extends Expr {
      val: number
   
      static at (i: ExternalObject, val: number): ConstInt {
         const this_: ConstInt = create(i, ConstInt)
         this_.val = __check(val, x => !Number.isNaN(x))
         this_.__version()
         return this_
      }
   }
   
   export class ConstStr extends Expr {
      val: string
   
      static at (i: ExternalObject, val: string): ConstStr {
         const this_: ConstStr = create(i, ConstStr)
         this_.val = val
         this_.__version()
         return this_
      }
   }
   
   export class Constr extends Expr {
      ctr: Lex.Ctr
      args: List<Expr>
   
      static at (i: ExternalObject, ctr: Lex.Ctr, args: List<Expr>): Constr {
         const this_: Constr = create(i, Constr)
         this_.ctr = ctr
         this_.args = args
         this_.__version()
         return this_
      }
   }

   export class Fun extends Expr {
      σ: Trie

      static at (i: ExternalObject, σ: Trie): Fun {
         const this_: Fun = create(i, Fun)
         this_.σ = σ
         this_.__version()
         return this_
      }
   }

   // A let is simply a match where the trie is a variable trie.
   export class Let extends Expr {
      e: Expr
      σ: Trie.Var

      static at (i: ExternalObject, e: Expr, σ: Trie.Var): Let {
         const this_: Let = create(i, Let)
         this_.e = e
         this_.σ = σ
         this_.__version()
         return this_
      }
   }

   export class PrimOp extends Expr {
      op: UnaryOp

      static at (i: ExternalObject, op: UnaryOp): PrimOp {
         const this_: PrimOp = create(i, PrimOp)
         this_.op = op
         this_.__version()
         return this_
      }
   }

   export class RecDef extends VersionedObject<ExternalObject> {
      x: Lex.Var
      e: Expr
   
      static at (α: ExternalObject, x: Lex.Var, e: Expr): RecDef {
         const this_: RecDef = create(α, RecDef)
         this_.x = x
         this_.e = e
         this_.__version()
         return this_
      }
   }

   export class LetRec extends Expr {
      δ: List<RecDef>
      e: Expr

      static at (i: ExternalObject, δ: List<RecDef>, e: Expr): LetRec {
         const this_: LetRec = create(i, LetRec)
         this_.δ = δ
         this_.e = e
         this_.__version()
         return this_
      }
   }

   export class MatchAs extends Expr {
      e: Expr
      σ: Trie
   
      static at (i: ExternalObject, e: Expr, σ: Trie): MatchAs {
         const this_: MatchAs = create(i, MatchAs)
         this_.e = e
         this_.σ = σ
         this_.__version()
         return this_
      }
   }

   export class PrimApp extends Expr {
      e1: Expr
      opName: Lex.OpName
      e2: Expr

      static at (i: ExternalObject, e1: Expr, opName: Lex.OpName, e2: Expr): PrimApp {
         const this_: PrimApp = create(i, PrimApp)
         this_.e1 = e1
         this_.opName = opName
         this_.e2 = e2
         this_.__version()
         return this_
      }
   }

   export class Var extends Expr {
      x: Lex.Var
   
      static at (i: ExternalObject, x: Lex.Var): Var {
         const this_: Var = create(i, Var)
         this_.x = x
         this_.__version()
         return this_
      }
   }
}

// Rename to Explained?
export class Traced<V extends Value = Value> extends PersistentObject {
   t: Trace
   v: V | null

   static make <V extends Value> (t: Trace, v: V | null): Traced<V> {
      const this_: Traced<V> = make<Traced<V>>(Traced, t, v)
      this_.t = t
      this_.v = v
      return this_
   }
}

// Tries used to have type parameter K, as per the formalism, but in TypeScript it didn't really help.
export type Kont = Expr | Traced | Trie | null

// Tries are persistent but not versioned, as per the formalism.
export type Trie = Trie.Trie

export namespace Trie {
   export class Trie extends PersistentObject implements JoinSemilattice<Trie> {

      join (σ: Trie): Trie {
         return join(this, σ)
      }
   }

   export class Prim extends Trie {
      body: Kont
   }

   export class ConstInt extends Prim {
      static make (body: Kont): ConstInt {
         const this_: ConstInt = make(ConstInt, body)
         this_.body = body
         return this_
      }
   }

   export class ConstStr extends Prim {
      static make (body: Kont): ConstStr {
         const this_: ConstStr = make(ConstStr, body)
         this_.body = body
         return this_
      }
   }

   export class Constr extends Trie {
      cases: FiniteMap<string, Kont>

      static make (cases: FiniteMap<string, Kont>): Constr {
         const this_: Constr = make(Constr, cases)
         this_.cases = cases
         return this_
      }
   }

   export class Fun extends Trie {
      body: Kont

      static make (body: Kont): Fun {
         const this_: Fun = make(Fun, body)
         this_.body = body
         return this_
      }
   }

   export class Var extends Trie {
      x: Lex.Var
      body: Kont

      static make (x: Lex.Var, body: Kont): Var {
         const this_: Var = make(Var, x, body)
         this_.x = x
         this_.body = body
         return this_
      }
   }

   // join of expressions is undefined, which effectively means case branches never overlap.
   function joinKont (κ: Kont, κʹ: Kont): Kont {
      if (κ instanceof Trie && κʹ instanceof Trie) {
         return join(κ, κʹ)
      } else {
         return assert(false, "Undefined join.", κ, κʹ)
      }
   }

   export function join (σ: Trie, τ: Trie): Trie {
      if (σ instanceof Fun && τ instanceof Fun) {
         return Fun.make(joinKont(σ.body, τ.body))
      } else
      if (σ instanceof Var && τ instanceof Var && eq(σ.x, τ.x)) {
         return Var.make(σ.x, joinKont(σ.body, τ.body))
      } else
      if (σ instanceof Constr && τ instanceof Constr) {
         return Constr.make(unionWith(σ.cases, τ.cases, joinKont))
      } else {
         return assert(false, "Undefined join.", σ, τ)
      }
   }
}

export class TracedMatch<T extends MatchedTrie> extends PersistentObject {
   t: Trace
   ξ: T

   static make<T extends MatchedTrie> (t: Trace, ξ: T): TracedMatch<T> {
      const this_: TracedMatch<T> = make<TracedMatch<T>>(TracedMatch, t, ξ)
      this_.t = t
      this_.ξ = ξ
      return this_
   }
}

export type MatchedTrie = MatchedTrie.MatchedTrie

export namespace MatchedTrie {
   export class MatchedTrie extends PersistentObject {
   }

   export class Prim extends MatchedTrie {
      κ: Kont
   }

   export class ConstInt extends Prim {
      val: number

      static make (val: number, κ: Kont): ConstInt {
         const this_: ConstInt = make(ConstInt, val, κ)
         this_.val = val
         this_.κ = κ
         return this_
      }
   }

   export class ConstStr extends Prim {
      val: string

      static make (val: string, κ: Kont): ConstStr {
         const this_: ConstStr = make(ConstStr, val, κ)
         this_.val = val
         this_.κ = κ
         return this_
      }
   }

   export class Constr extends MatchedTrie {
   }

   export class Fun extends MatchedTrie {
      ρ: Env
      σ: Trie
      κ: Kont

      static make (ρ: Env, σ: Trie, κ: Kont): Fun {
         const this_: Fun = make(Fun, ρ, σ, κ)
         this_.ρ = ρ
         this_.σ = σ
         this_.κ = κ
         return this_
      }
   }

   // Is there any extra information a matched variable trie should carry?
   export class Var extends MatchedTrie {
      x: Lex.Var
      body: Kont

      static make (x: Lex.Var, body: Kont): Var {
         const this_: Var = make(Var, x, body)
         this_.x = x
         this_.body = body
         return this_
      }
   }
}

export type Trace = Trace.Trace

export namespace Trace {
   export class Trace extends VersionedObject<Runtime<Expr>> {
      __Trace(): void {
         // discriminator
      }
   }
   
   export class App extends Trace {
      func: Traced
      arg: Traced
      body: Trace | null

      static at (k: Runtime<Expr>, func: Traced, arg: Traced, body: Trace | null): App {
         const this_: App = create(k, App)
         this_.func = func
         this_.arg = arg
         this_.body = body
         this_.__version()
         return this_
      }
   }

   // Not the same as ⊥ (null); we distinguish information about an absence from the absence of information.
   export class Empty extends Trace {
      static at (k: Runtime<Expr>): Empty {
         const this_: Empty = create(k, Empty)
         this_.__version()
         return this_
      }
   }

   export class Let extends Trace {
      tu: Traced
      σ: Trie.Var
      t: Trace | null

      __Let (): void {
         // discriminator
      }

      static at (k: Runtime<Expr>, tu: Traced, σ: Trie.Var, t: Trace | null): Let {
         const this_: Let = create(k, Let)
         this_.tu = tu
         this_.σ = σ
         this_.t = t
         this_.__version()
         return this_
      }
   }

   export class RecDef extends VersionedObject<Runtime<Expr.RecDef>> {
      x: Lex.Var
      tv: Traced
   
      static at (i: Runtime<Expr.RecDef>, x: Lex.Var, tv: Traced): RecDef {
         const this_: RecDef = create(i, RecDef)
         this_.x = x
         this_.tv = tv
         this_.__version()
         return this_
      }
   }

   // Continuation here should really be a trace, not a traced value.
   export class LetRec extends Trace {
      δ: List<RecDef>
      tv: Traced
   
      static at (k: Runtime<Expr>, δ: List<RecDef>, tv: Traced): LetRec {
         const this_: LetRec = create(k, LetRec)
         this_.δ = δ
         this_.tv = tv
         this_.__version()
         return this_
      }
   }
   
   export class MatchAs extends Trace {
      tu: Traced
      σ: Trie
      t: Trace | null

      __Match (): void {
         // discriminator
      }

      static at (k: Runtime<Expr>, tu: Traced, σ: Trie,  t: Trace | null): MatchAs {
         const this_: MatchAs = create(k, MatchAs)
         this_.tu = tu
         this_.σ = σ
         this_.t = t
         this_.__version()
         return this_
      }
   }

   export class PrimApp extends Trace {
      tv1: Traced
      opName: Lex.OpName
      tv2: Traced

      static at (k: Runtime<Expr>, tv1: Traced, opName: Lex.OpName, tv2: Traced): PrimApp {
         const this_: PrimApp = create(k, PrimApp)
         this_.tv1 = tv1
         this_.opName = opName
         this_.tv2 = tv2
         this_.__version()
         return this_
      }
   }

   export class Var extends Trace {
      x: Lex.Var
      t: Trace | null

      static at (k: Runtime<Expr>, x: Lex.Var, t: Trace | null): Var {
         const this_: Var = create(k, Var)
         this_.x = x
         this_.t = t
         this_.__version()
         return this_
      }
   }
}
