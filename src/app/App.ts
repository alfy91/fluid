import { __nonNull } from "../util/Core"
import { ann } from "../util/Lattice"
import { setallα, negateallα } from "../Annotated"
import { ExplValue } from "../DataValue"
import { __deltas } from "../Delta"
import { Env } from "../Env"
import { Direction, Eval } from "../Eval"
import { Expr } from "../Expr"
import  { GraphicsElement } from "../Graphics"
import { openWithImports, openDatasetAs, parseWithImports } from "../Module"
import { newRevision } from "../Versioned"
import { GraphicsRenderer, Slicer, ViewCoordinator } from "./GraphicsRenderer"
import { svgRootElement } from "./Renderer"

// As with the test cases, we treat the dataset ρ as "external" data, meaning we push slicing
// information back only as far as ρ.
export class View implements Slicer {
   name: string
   coordinator!: ViewCoordinator
   e: Expr
   tv: ExplValue
   view: GraphicsRenderer
   direction!: Direction

   constructor (name: string, ρ: Env, e: Expr, svg: SVGElement) {
      this.name = name
      this.e = e
      this.tv = Eval.eval_(ρ, e)
      this.view = new GraphicsRenderer(svg, this)
      this.fwdSlice()
      this.draw()
   }

   // See #234 for repeated use of newRevision.

   // Consider (un)availability of dataset only; treat e as an unlimited resource.
   fwdSlice (): void {
      newRevision()
      setallα(ann.top, this.e)
      Eval.eval_fwd(this.e, this.tv)
      this.direction = Direction.Fwd
      this.draw()
   }
   
   // Clear annotations on program and forward slice, to erase all annotations prior to backward slicing.
   resetForBwd (): void {
      newRevision()
      setallα(ann.bot, this.e)
      Eval.eval_fwd(this.e, this.tv)
      newRevision()
   }

   bwdSlice (): void {
      Eval.eval_bwd(this.e, this.tv)
      this.direction = Direction.Bwd
      this.coordinator.onBwd()
      this.draw()
   }

   get svg (): SVGSVGElement {
      return this.view.ancestors[0] as SVGSVGElement
   }

   getGraphics (): ExplValue<GraphicsElement> {
      return this.tv as ExplValue<GraphicsElement>
   }

   draw (): void {
      this.view.render(this.getGraphics())
   }
}

// Data has approximate recursive type
// Data = Versioned<List<Pair<Num | Str, Data>>>

class App {
   dataView: View
   graphicsView: View

   constructor () {
      const ρ: Env = openDatasetAs("renewables", "data")
      newRevision()
      setallα(ann.top, ρ)
      this.graphicsView = new View(
         "graphicsView", 
         ρ,
         openWithImports("bar-chart"), // module_graphics
         svgRootElement(400, 400)
      )
      this.dataView = new View(
         "dataView", 
         ρ,
         parseWithImports("renderData data"), // module_renderData, module_graphics
         svgRootElement(400, 1200)
      )
      const dataView: View = this.dataView
      this.graphicsView.coordinator = new class ViewCoordinator {
         onBwd (): void {
            newRevision()
            negateallα(ρ)
            dataView.fwdSlice()
         }

         resetForBwd (): void {
            newRevision()
            setallα(ann.bot, ρ)
            dataView.resetForBwd()
            graphicsView.resetForBwd()
         }
      }()
      const graphicsView: View = this.graphicsView
      this.dataView.coordinator = new class ViewCoordinator {
         onBwd (): void {
            newRevision()
            negateallα(ρ)
            graphicsView.fwdSlice()
         }

         resetForBwd (): void {
            newRevision()
            setallα(ann.bot, ρ)
            dataView.resetForBwd()
            graphicsView.resetForBwd()
         }
      }
      document.body.appendChild(this.dataView.svg)
      document.body.appendChild(this.graphicsView.svg)
   }
}

new App()
