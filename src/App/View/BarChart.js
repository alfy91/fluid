"use strict"

import * as d3 from "d3"

// This prelude currently duplicated across all FFI implementations.
function curry2 (f) {
   return x1 => x2 => f(x1, x2)
}

function curry3 (f) {
   return x1 => x2 => x3 => f(x1, x2, x3)
}

function curry4 (f) {
   return x1 => x2 => x3 => x4 => f(x1, x2, x3, x4)
}

function Sel_isNone (v) {
   return v.tag == "None"
}

function Sel_isPrimary (v) {
   return v.tag == "Primary"
}

function Sel_isSecondary (v) {
   return v.tag == "Secondary"
}

function fst(p) {
   return p._1
}

function snd(p) {
   return p._2
}

// https://stackoverflow.com/questions/5560248
function colorShade (col, amt) {
   col = col.replace(/^#/, '')
   if (col.length === 3) col = col[0] + col[0] + col[1] + col[1] + col[2] + col[2]

   let [r, g, b] = col.match(/.{2}/g);
   ([r, g, b] = [parseInt(r, 16) + amt, parseInt(g, 16) + amt, parseInt(b, 16) + amt])

   r = Math.max(Math.min(255, r), 0).toString(16)
   g = Math.max(Math.min(255, g), 0).toString(16)
   b = Math.max(Math.min(255, b), 0).toString(16)

   const rr = (r.length < 2 ? '0' : '') + r
   const gg = (g.length < 2 ? '0' : '') + g
   const bb = (b.length < 2 ? '0' : '') + b

   return `#${rr}${gg}${bb}`
}

function drawBarChart_ (
   id,
   suffix,
   {
      caption,    // String
      data,       // Array StackedBar
   },
   listener
) {
   return () => {
      const childId = id + '-' + suffix
      const margin = {top: 15, right: 0, bottom: 40, left: 40},
            width = 200 - margin.left - margin.right,
            height = 185 - margin.top - margin.bottom
      const div = d3.select('#' + id)

      div.selectAll('#' + childId).remove()

      const svg = div
         .append('svg')
            .attr('width', width + margin.left + margin.right)
            .attr('height', height + margin.top + margin.bottom)
         .attr('id', childId)
         .append('g')
            .attr('transform', `translate(${margin.left}, ${margin.top})`)

      // x-axis
      const x = d3.scaleBand()
         .range([0, width])
         .domain(data.map(d => fst(d.x)))
         .padding(0.2)
      svg.append('g')
         .attr('transform', "translate(0," + height + ")")
         .call(d3.axisBottom(x))
         .selectAll('text')
            .style('text-anchor', 'middle')

      // y-axis
      const nearest = 100,
            y_max = Math.ceil(Math.max(...data.map(d => fst(d.bars[0].z))) / nearest) * nearest
      const y = d3.scaleLinear()
         .domain([0, y_max])
         .range([height, 0])
      const tickEvery = 100,
            ticks = Array.from(Array(Math.ceil(y_max / tickEvery + 1)).keys()).map(n => n * tickEvery)
      const yAxis = d3.axisLeft(y)
         .tickValues(ticks)
      svg.append('g')
         .call(yAxis)

      // bars
      const barFill = '#dcdcdc'
      const stacks = svg.selectAll('.stack')
         .data([...data.entries()])
         .enter()
         .append('g')

      stacks.selectAll('.bar')
         .data(([, {x, bars}]) => bars.slice(1).reduce((acc, bar) => {
            const y = acc[acc.length - 1].y + bar.z
            acc.push({x, y, height: bar.z})
            return acc
         }, [{x: x, y: 0, height: bars[0].z}]))
         .enter()
         .append('rect')
            .attr('x', bar => { return x(fst(bar.x)) })
            .attr('y', bar => { return y(fst(bar.y)) })  // ouch: bars overplot x-axis!
            .attr('width', x.bandwidth())
            .attr('height', bar => height - y(fst(bar.height)))
            .attr('fill', bar => Sel_isNone(snd(bar.height)) ? barFill : colorShade(barFill, -40))
            .attr('class', bar => Sel_isNone(snd(bar.height)) ? 'bar-unselected' : 'bar-selected')
            .on('mousedown', (e, d) => { listener(e) })

      svg.append('text')
         .text(fst(caption))
         .attr('x', width / 2)
         .attr('y', height + 35)
         .attr('class', 'title-text')
         .attr('dominant-baseline', 'bottom')
         .attr('text-anchor', 'middle')
   }
}

export var drawBarChart = curry4(drawBarChart_)
