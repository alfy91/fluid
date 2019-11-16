import { Class, __nonNull, absurd, as, assert, classOf } from "../util/Core"
import { Cons, List, None, Pair, Some } from "../BaseTypes"
import { ExplValue } from "../DataValue"
import { Group, GraphicsElement, Marker, Polyline, Rect, Scale, Transform, Translate } from "../Graphics2"
import { Unary, unary_, unaryOps } from "../Primitive"
import { Id, Num, Str } from "../Value"
import { num } from "../Versioned"
import { SVG } from "./Core"
import { ExplValueCursor } from "./Cursor"
import { line, markerEnsureDefined, polyline, rect, svgElement, textElement_graphical } from "./Renderer"

const fontSize: number = 12

export const svg: SVG = new SVG()

type TransformFun = (x: number, y: number) => [number, number]

function scale (x_scale: number, y_scale: number): TransformFun {
   return (x, y): [number, number] => {
      return [x * x_scale, y * y_scale]
   }
}

function translate (x_inc: number, y_inc: number): TransformFun {
   return (x, y): [number, number] => {
      return [x + x_inc, y + y_inc]
   }
}

function transformFun (t: Transform): TransformFun {
   if (t instanceof Scale) {
      assert(t.x.val >= 0 && t.y.val >= 0)
      return scale(t.x.val, t.y.val)
   } else
   if (t instanceof Translate) {
      return translate(t.x.val, t.y.val)
   } else {
      return absurd()
   }
}

function transformFuns (...ts: Transform[]): TransformFun[] {
   return ts.map(t => transformFun(as(t, Transform)))
}

function postcompose (f1: TransformFun, f2: TransformFun): TransformFun {
   return (x, y): [number, number] => {
      let [x_, y_] = f2(x, y)
      return f1(x_, y_)
   }
}

export class GraphicsRenderer {
   root: SVGSVGElement
   ancestors: SVGElement[] // stack of enclosing SVG elements
   transforms: TransformFun[] // stack of successive compositions of linear transformations

   // transform attribute isn't supported on SVGElement, so it contains a group element with the inversion transform.
   constructor (root: SVGSVGElement, initialAncestor: SVGElement) {
      this.root = root
      this.ancestors = [initialAncestor]
      this.transforms = [(x, y) => [x, y]]
   }

   get current (): SVGElement {
      return this.ancestors[this.ancestors.length - 1]
   }

   // rounding is problematic
   get transform (): TransformFun {
      assert(this.transforms.length > 0)
      return this.transforms[this.transforms.length - 1] 
   }

   render (tg: ExplValue<GraphicsElement>, [w, h]: [number, number]): void {
      assert(this.ancestors.length === 1)
      const root: SVGElement = this.current
      while (root.firstChild !== null) {
         root.removeChild(root.firstChild)
      }
      const width: number = parseFloat(__nonNull(root.getAttribute("width")))
      const height: number = parseFloat(__nonNull(root.getAttribute("height")))
      this.withLocalTransforms([scale(width / w, height / h)], () => {
         this.renderElement(ExplValueCursor.descendant(null, tg))
      })
   }

   renderElement (tg: ExplValueCursor/*<GraphicsElement>*/): void {
      const g: GraphicsElement = as(tg.tv.v, GraphicsElement)
      if (g instanceof Group) {
         this.group(tg)
      } else 
      if (g instanceof Rect) {
         this.rect(tg)
      } else
      if (g instanceof Polyline) {
         this.polyline(tg)
      } else {
         return absurd()
      }
   }

   withLocalTransforms<T> (ts: TransformFun[], localRender: () => T): T {
      let result: T
      ts.forEach(t => {
         this.transforms.push(postcompose(this.transform, t))
      })
      result = localRender()
      ts.forEach(_ => {
         this.transforms.pop()
      })
      return result
   }

   group (tg: ExplValueCursor/*<Graphic>*/): void {
      const g: Group = as(tg.tv.v, Group)
      // dimensions are relative to parent coordinate space, so not transformed by g's scaling
      const [x, y] = this.transform(g.x.val, g.y.val)
      const [x2, y2] = this.transform(g.x.val + g.width.val, g.y.val + g.height.val)
      const [width, height] = [x2 - x, y2 - y]
      assert(width >= 0 && height >= 0)
      const svg: SVGSVGElement = svgElement(x, y, width, height, false, this.group)
      this.current.appendChild(svg)
      this.ancestors.push(svg)
      this.withLocalTransforms(transformFuns(g.scale, g.translate), () => { // scaling applies to translated coordinates
         for (let tg̅: ExplValueCursor/*<List<GraphicsElement>>*/ = tg.to(Group, "gs"); 
         Cons.is(as(tg̅.tv.v, List)); tg̅ = tg̅.to(Cons, "tail")) {
            this.renderElement(tg̅.to(Cons, "head"))
         }
      })
      this.ancestors.pop()
   }

   rect (tg: ExplValueCursor/*<Rect>*/): void {
      const g: Rect = as(tg.tv.v, Rect)
      const [x, y] = this.transform(g.x.val, g.y.val)
      const [x2, y2] = this.transform(g.x.val + g.width.val, g.y.val + g.height.val)
      const [width, height] = [x2 - x, y2 - y]
      assert(width >= 0 && height >= 0)
      const r: SVGRectElement = rect(x, y, width, height, "none", g.fill.val)
      this.current.appendChild(r)
   }

   polyline (tg: ExplValueCursor/*<Polyline>*/): void {
      const g: Polyline = as(tg.tv.v, Polyline)
      // each point is considered a "child", and therefore subject to my local scaling
      const ps: [number, number][] = this.withLocalTransforms(transformFuns(g.scale), () => {
         return g.points.toArray().map((p: Pair<Num, Num>): [number, number] => {
            return this.transform(p.fst.val, p.snd.val)
         })
      })
      // Optimise polyline with 2 points to line. TODO: what about when there is only one point?
      let line_: SVGElement
      if (ps.length === 2) {
         const [[x1, y1], [x2, y2]] = ps
         line_ = line(x1, y1, x2, y2, g.stroke.val)
      } else {
         line_ = polyline(ps, g.stroke.val)
      }
      if (Some.is(g.marker)) {
         this.setMarkerMid(line_, classOf(g.marker.t), g.stroke.val)
      } else {
         assert(None.is(g.marker))
      }
      this.current.appendChild(line_)
   }

   setMarkerMid (el: SVGElement, C: Class<Marker>, colour: string): void {
      const markerId: string = markerEnsureDefined(this.root, C, colour) // revisit cast
      el.setAttribute("marker-mid", `url(#${markerId})`)
   }
}

{
   // Additional primitives that rely on offline rendering to compute text metrics. Combining these would 
   // require more general primitives that can return tuples.
   const textWidth: Unary<Str, Num> = (str: Str): (k: Id) => Num => {
      return num(svg.textWidth(textElement_graphical(0, 0, fontSize, str.val)))
   }
   
   const textHeight: Unary<Str, Num> = (str: Str): (k: Id) => Num => {
      return num(svg.textHeight(textElement_graphical(0, 0, fontSize, str.val)))
   }
   
   unaryOps.set(textWidth.name, unary_(textWidth))
   unaryOps.set(textHeight.name, unary_(textHeight))
}
