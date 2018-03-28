import { __nonNull, as, assert, abstractMethodError } from "./util/Core"
import { unionWith } from "./util/Map"
import { JoinSemilattice, eq } from "./util/Ord"
import { Lexeme } from "./util/parse/Core"
import { __def, key } from "./Memo"
import { partiallyApply, PrimBody } from "./Primitive"
import { binaryOps, create, unaryOps } from "./Runtime"

export class EnvEntry {
   ρ: Env
   δ: Expr.RecDefinition[]
   e: Expr.Expr

   constructor(ρ: Env, δ: Expr.RecDefinition[], e: Expr.Expr) {
      this.ρ = ρ
      this.δ = δ
      this.e = e
   }
}

export type Env = Map<string, EnvEntry | null>

export namespace str {
   // Primitive ops.
   export const concat: string = "++"
   export const div: string = "/"
   export const equal: string = "=="
   export const greaterT: string = ">"
   export const lessT: string = "<"
   export const minus: string = "-"
   export const plus: string = "+"
   export const times: string = "*"

   // Constants used for parsing, and also for toString() implementations.
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
   // With purely structural typing, these lexeme classes are identical, not just isomorphic. This
   // mostly sucks in a class-oriented languages like JavaScript, so we add dummy discriminator methods.

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

export namespace Value {
   export type Value = Closure | ConstInt | ConstStr | Constr | PrimOp

   export class Closure {
      ρ: Env
      δ: Expr.RecDefinition[]
      func: Expr.Fun
   
      static at (α: Addr, ρ: Env, δ: Expr.RecDefinition[], func: Expr.Fun): Closure {
         const this_: Closure = create(α, Closure)
         this_.ρ = ρ
         this_.δ = δ
         this_.func = as(func, Expr.Fun)
         this_.__version()
         return this_
      }
   }
   
   export class ConstInt {
      val: number
   
      static at (α: Addr, val: number): ConstInt {
         const this_: ConstInt = create(α, ConstInt)
         this_.val = val
         this_.__version()
         return this_
      }
   }
   
   export class ConstStr {
      val: string
   
      static at (α: Addr, val: string): ConstStr {
         const this_: ConstStr = create(α, ConstStr)
         this_.val = val
         this_.__version()
         return this_
      }
   }
   
   export class Constr {
      ctr: Lex.Ctr
      args: Traced[]
   
      static at (α: Addr, ctr: Lex.Ctr, args: Traced[]): Constr {
         const this_: Constr = create(α, Constr)
         this_.ctr = as(ctr, Lex.Ctr)
         this_.args = args
         this_.__version()
         return this_
      }
   }

   // Primitive ops; see 0.4.4 release notes.
   export class PrimOp {
      σ: Trie.Prim<PrimBody>

      _apply<T> (v: Value.Value | null, σ: Trie.Trie<T>): Value.Value | null {
         if (v === null) {
            return null
         } else {
            return this.__apply(v)
         }
      }
   
      __apply (v: Value.Value): Value.Value {
         return abstractMethodError(this)
      }
   }
   
   // Assume all dynamic type-checking is performed inside the underlying JS operation, although
   // currently there mostly isn't any.
   export class UnaryPrimOp extends PrimOp {
      name: string
   
      static at (α: Addr, name: string): UnaryPrimOp {
         const this_: UnaryPrimOp = create(α, UnaryPrimOp)
         this_.name = name
         this_.__version()
         return this_
      }
   
      __apply (v: Value.Value): Value.Value {
         return __nonNull(unaryOps.get(this.name))(v)
      }
   
      toString (): string {
         return this.name
      }
   }
   
   export class BinaryPrimOp extends PrimOp {
      name: string
   
      static at (α: Addr, name: string): BinaryPrimOp {
         const this_: BinaryPrimOp = create(α, BinaryPrimOp)
         this_.name = name
         this_.__version()
         return this_
      }
   
      __apply (v1: Value.Value): PrimOp {
         return partiallyApply(this, v1)
      }
      
      toString (): string {
         return this.name
      }
   }
   
   // Binary op that has been applied to a single operand. Should be a UnaryPrimOp, but TypeScript
   // forces static methods to "override".
   export class UnaryPartialPrimOp extends PrimOp {
      name: string
      binOp: BinaryPrimOp
      v1: Value.Value
   
      static at (α: Addr, name: string, binOp: BinaryPrimOp, v1: Value.Value): UnaryPartialPrimOp {
         const this_: UnaryPartialPrimOp = create(α, UnaryPartialPrimOp)
         this_.name = name
         this_.binOp = as(binOp, BinaryPrimOp)
         this_.v1 = v1
         this_.__version()
         return this_
      }
   
      __apply (v2: Value.Value): Value.Value {
         return __nonNull(binaryOps.get(this.binOp.name))(this.v1, v2)
      }
   
      toString (): string {
         return this.name
      }
   }
}

export namespace Expr {
   export class Expr {
      __Expr(): void {
         // discriminator
      }
   }

   export class App extends Expr {
      func: Expr
      arg: Expr

      static at (α: Addr, func: Expr, arg: Expr): App {
         const this_: App = create(α, App)
         this_.func = as(func, Expr)
         this_.arg = as(arg, Expr)
         this_.__version()
         return this_
      }
   }

   export class ConstInt extends Expr {
      val: number
   
      static at (α: Addr, val: number): ConstInt {
         const this_: ConstInt = create(α, ConstInt)
         this_.val = val
         this_.__version()
         return this_
      }
   }
   
   export class ConstStr extends Expr {
      val: string
   
      static at (α: Addr, val: string): ConstStr {
         const this_: ConstStr = create(α, ConstStr)
         this_.val = val
         this_.__version()
         return this_
      }
   }
   
   export class Constr extends Expr {
      ctr: Lex.Ctr
      args: Expr[]
   
      static at (α: Addr, ctr: Lex.Ctr, args: Expr[]): Constr {
         const this_: Constr = create(α, Constr)
         this_.ctr = as(ctr, Lex.Ctr)
         this_.args = args
         this_.__version()
         return this_
      }
   }

   export class Fun extends Expr {
      σ: Trie.Trie<Expr>

      static at (α: Addr, σ: Trie.Trie<Expr>): Fun {
         const this_: Fun = create(α, Fun)
         this_.σ = as(σ, Trie.Trie)
         this_.__version()
         return this_
      }
   }

   // A let is simply a match where the trie is a variable trie.
   export class Let extends Expr {
      e: Expr
      σ: Trie.Var<Expr>

      static at (α: Addr, e: Expr, σ: Trie.Var<Expr>): Let {
         const this_: Let = create(α, Let)
         this_.e = as(e, Expr)
         this_.σ = as(σ, Trie.Var)
         this_.__version()
         return this_
      }
   }

   export class RecDefinition {
      name: Lex.Var
      func: Fun
   
      static at (α: Addr, name: Lex.Var, func: Fun): RecDefinition {
         const this_: RecDefinition = create(α, RecDefinition)
         this_.name = as(name, Lex.Var)
         this_.func = as(func, Fun)
         this_.__version()
         return this_
      }
   }
   
   export class LetRec extends Expr {
      δ: RecDefinition[]
      e: Expr

      static at (α: Addr, δ: RecDefinition[], e: Expr): LetRec {
         const this_: LetRec = create(α, LetRec)
         this_.δ = δ
         this_.e = as(e, Expr)
         this_.__version()
         return this_
      }
   }

   export class MatchAs extends Expr {
      e: Expr
      σ: Trie.Trie<Expr>
   
      static at (α: Addr, e: Expr, σ: Trie.Trie<Expr>): MatchAs {
         const this_: MatchAs = create(α, MatchAs)
         this_.e = as(e, Expr)
         this_.σ = as(σ, Trie.Trie)
         this_.__version()
         return this_
      }
   }

   export class OpName extends Expr {
      opName: Lex.OpName
   
      static at (α: Addr, opName: Lex.OpName): OpName {
         const this_: OpName = create(α, OpName)
         this_.opName = as(opName, Lex.OpName)
         this_.__version()
         return this_
      }
   }

   // Like a (traditional) function literal wraps an expression, a prim op literal wraps a prim op; however
   // we never bundle such a thing into a closure, but simply unwrap the contained prim op.
   export class PrimOp extends Expr {
      op: Value.PrimOp

      static at (α: Addr, op: Value.PrimOp): PrimOp {
         const this_: PrimOp = create(α, PrimOp)
         this_.op = op
         this_.__version()
         return this_
      }
   }

   export class Var extends Expr {
      ident: Lex.Var
   
      static at (α: Addr, ident: Lex.Var): Var {
         const this_: Var = create(α, Var)
         this_.ident = as(ident, Lex.Var)
         this_.__version()
         return this_
      }
   }
}

export class Traced<T extends Value.Value = Value.Value> {
   trace: Trace.Trace
   val: T | null

   static at <T extends Value.Value> (α: Addr, trace: Trace.Trace, val: T | null): Traced<T> {
      const this_: Traced<T> = create<Traced<T>>(α, Traced)
      this_.trace = as(trace, Trace.Trace)
      this_.val = val
      this_.__version()
      return this_
   }
}

export namespace Trie {
   // Not abstract, so that I can assert it as a runtime type. Shouldn't T extend JoinSemilattice<T>?
   export class Trie<T> implements JoinSemilattice<Trie<T>> {
      join (σ: Trie<T>): Trie<T> {
         return join(this, σ)
      }
   }

   // Refine this when we have proper signatures for primitive ops.
   export class Prim<T> extends Trie<T> {
      body: T

      static at <T> (α: Addr, body: T): Prim<T> {
         const this_: Prim<T> = create<Prim<T>>(α, Fun)
         this_.body = body
         this_.__version()
         return this_
      }
   }

   export class Constr<T> extends Trie<T> {
      cases: Map<string, T>

      static at <T> (α: Addr, cases: Map<string, T>): Constr<T> {
         const this_: Constr<T> = create<Constr<T>>(α, Constr)
         this_.cases = cases
         this_.__version()
         return this_
      }
   }

   export class Var<T> extends Trie<T> {
      x: Lex.Var
      body: T

      static at <T> (α: Addr, x: Lex.Var, body: T): Var<T> {
         const this_: Var<T> = create<Var<T>>(α, Var)
         this_.x = as(x, Lex.Var)
         this_.body = body
         this_.__version()
         return this_
      }
   }

   export class Fun<T> extends Trie<T> {
      body: T

      static at <T> (α: Addr, body: T): Fun<T> {
         const this_: Fun<T> = create<Fun<T>>(α, Fun)
         this_.body = body
         this_.__version()
         return this_
      }
   }

   // Addressing scheme doesn't yet support "member functions". Plus methods don't allow null receivers.
   __def(join)
   export function join <T extends JoinSemilattice<T>> (σ: Trie<T>, τ: Trie<T>): Trie<T> {
      const α: Addr = key(join, arguments)
      if (σ === null) {
         return τ
      } else
      if (τ === null) {
         return σ
      } else
      // The instanceof guards turns T into 'any'. Yuk.
      if (σ instanceof Fun && τ instanceof Fun) {
         const [σʹ, τʹ]: [Fun<T>, Fun<T>] = [σ, τ]
         return Fun.at(α, join(σʹ.body, τʹ.body))
      } else
      if (σ instanceof Var && τ instanceof Var && eq(σ.x, τ.x)) {
         const [σʹ, τʹ]: [Var<T>, Var<T>] = [σ, τ]
         return Var.at(α, σʹ.x, join(σʹ.body, τʹ.body))
      } else
      if (σ instanceof Constr && τ instanceof Constr) {
         const [σʹ, τʹ]: [Constr<T>, Constr<T>] = [σ, τ]
         return Constr.at<T>(α, unionWith([σʹ.cases, τʹ.cases], ms => ms.reduce((x, y) => x.join(y))))
      } else {
         return assert(false, "Undefined join.", σ, τ)
      }
   }
}

export namespace Trace {
   export class Trace {
      __Trace(): void {
         // discriminator
      }
   }
   
   export class App extends Trace {
      func: Traced
      arg: Traced
      body: Trace

      static at (α: Addr, func: Traced, arg: Traced, body: Trace): App {
         const this_: App = create(α, App)
         this_.func = as(func, Traced)
         this_.arg = as(arg, Traced)
         this_.body = as(body, Trace)
         this_.__version()
         return this_
      }
   }

   // I don't think this is the same as ⊥; it represents the "end" of an explanation.
   export class Empty extends Trace {
      static at (α: Addr): Empty {
         const this_: Empty = create(α, Empty)
         this_.__version()
         return this_
      }
   }

   export class Let extends Trace {
      tu: Traced
      t: Trace

      static at (α: Addr, tu: Traced, t: Trace): Match {
         const this_: Match = create(α, Match)
         this_.tu = as(tu, Traced)
         this_.t = as(t, Trace)
         this_.__version()
         return this_
      }
   }

   // Used to be something called RecBinding, but bindings doesn't seem to be stored in traces at the moment.
   export class LetRec extends Trace {
      δ: Expr.RecDefinition[]
      t: Trace
   
      static at (α: Addr, δ: Expr.RecDefinition[], t: Trace): LetRec {
         const this_: LetRec = create(α, LetRec)
         this_.δ = δ
         this_.t = as(t, Trace)
         this_.__version()
         return this_
      }
   }
   
      // See 0.6.1 release notes. Also 0.6.4 notes for discussion of expression/trace disparity.
   export class Match extends Trace {
      tu: Traced
      t: Trace

      static at (α: Addr, tu: Traced, t: Trace): Match {
         const this_: Match = create(α, Match)
         this_.tu = as(tu, Traced)
         this_.t = as(t, Trace)
         this_.__version()
         return this_
      }
   }

   export class OpName extends Trace {
      x: Lex.OpName
      t: Trace

      static at (α: Addr, x: Lex.OpName, t: Trace): OpName {
         const this_: OpName = create(α, OpName)
         this_.x = as(x, Lex.OpName)
         this_.t = as(t, Trace)
         this_.__version()
         return this_
      }
   }

   // For primitives there is no body, but we will still show how the argument is consumed.
   export class PrimApp extends Trace {
      op: Traced
      arg: Traced

      static at (α: Addr, op: Traced, arg: Traced): PrimApp {
         const this_: PrimApp = create(α, PrimApp)
         this_.op = as(op, Traced)
         this_.arg = as(arg, Traced)
         this_.__version()
         return this_
      }
   }

   export class Var extends Trace {
      x: Lex.Var
      t: Trace

      static at (α: Addr, x: Lex.Var, t: Trace): Var {
         const this_: Var = create(α, Var)
         this_.x = as(x, Lex.Var)
         this_.t = as(t, Trace)
         this_.__version()
         return this_
      }
   }
}
