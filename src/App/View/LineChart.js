"use strict"

import * as d3 from "d3"

d3.selection.prototype.attrs = function(m) {
   for (const k in m) {
      this.attr(k, m[k])
   }
   return this
}

function setSelState (
   { point_attrs },
   { },
   nameCol,
   rootElement,
   chart,
   listener
) {
   rootElement.selectAll('.linechart-point').each(function (point) {
      d3.select(this) // won't work inside arrow function :/
         .attrs(point_attrs(nameCol)(chart)(point))
         .on('mousedown', e => { listener(e) })
         .on('mouseenter', e => { listener(e) })
         .on('mouseleave', e => { listener(e) })
   })
}

function drawLineChart_ (
   lineChartHelpers,
   { val,
     selState,
     selClasses,
     selClassesFor
   },
   {
      divId,
      suffix,
      view: {
         caption,   // String
         plots,     // Array LinePlot
      }
   },
   listener
) {
   return () => {
      const { margin, width, height, x_ticks, y_ticks, to_x, to_y, legendHelpers, caption_attrs }
         = lineChartHelpers
      const childId = divId + '-' + suffix
      const names = plots.map(plot => val(plot.name))
      const div = d3.select('#' + divId)
      if (div.empty()) {
         console.error('Unable to insert figure: no div found with id ' + divId)
         return
      }

      let rootElement = div.selectAll('#' + childId)
      const color = d3.scaleOrdinal(d3.schemePastel1)

      function nameCol (name) {
         return color(names.indexOf(name))
      }

      if (rootElement.empty()) {
         rootElement = div
            .append('svg')
            .attr('width', width + margin.left + margin.right)
            .attr('height', height + margin.top + margin.bottom)
            .attr('id', childId)
            .append('g')
            .attr('transform', `translate(${margin.left}, ${margin.top})`)

         const line1 = d3.line()
            .x(d => to_x(val(d.x)))
            .y(d => to_y(val(d.y)))

         rootElement.selectAll('line')
            .data([...plots.entries()])
            .enter()
            .append('path')
            .attr('fill', 'none')
            .attr('stroke', ([, plot]) => nameCol(val(plot.name)))
            .attr('stroke-width', 1)
            .attr('class', 'line')
            .attr('d', ([, plot]) => line1(plot.points))

         for (const [i, plot] of plots.entries()) {
            rootElement.selectAll('linechart-point')
               .data([...plot.points.entries()].map(([j, p]) => {
                  return { name: val(plot.name), x: val(p.x), y: val(p.y), i, j }
               }))
               .enter()
               .append('circle')
               .attr('class', 'linechart-point')
         }

         rootElement
            .append('g')
            .attr('transform', `translate(0, ${height})`)
            .call(d3.axisBottom(to_x).ticks(x_ticks).tickFormat(d3.format('d')))

         rootElement
            .append('g')
            .call(d3.axisLeft(to_y).tickSizeOuter(0).ticks(y_ticks).tickFormat(d3.format('.1f')))

         const legend = rootElement.append('g')
            .attr('transform', `translate(${legendHelpers.x}, 0)`)

         legend.append('rect')
            .attrs(legendHelpers.box_attrs)

         const legendEntry = legend.selectAll('legend-entry')
            .data(names)
            .enter()
            .append('g')
            .attr('transform', (d, i) =>
               `translate(0, ${legendHelpers.entry_y(i)})`
            )

         legendEntry.append('text')
            .text(d => d)
            .attrs(legendHelpers.text_attrs)

         legendEntry.append('circle')
            .attr('fill', d => nameCol(d))
            .attrs(legendHelpers.circle_attrs)

         rootElement
            .append('text')
            .text(val(caption))
            .attrs(caption_attrs)
      }
      setSelState(lineChartHelpers, { selState, selClasses, selClassesFor}, nameCol, rootElement, { plots }, listener)
   }
}

export var drawLineChart = x1 => x2 => x3 => x4 => drawLineChart_(x1, x2, x3, x4)
export var scaleLinear = x1 => x2 => d3.scaleLinear().domain([x1.min, x1.max]).range([x2.min, x2.max])
