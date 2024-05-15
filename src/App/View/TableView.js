"use strict"

import * as d3 from "d3"

// =================================================================
// This prelude currently duplicated across all FFI implementations.
// =================================================================

function curry2 (f) {
   return x1 => x2 => f(x1, x2)
}

function curry3 (f) {
   return x1 => x2 => x3 => f(x1, x2, x3)
}

function curry4 (f) {
   return x1 => x2 => x3 => x4 => f(x1, x2, x3, x4)
}

function isCtr (v, i, ctrs) {
   const j = ctrs.indexOf(v.tag)
   if (j == -1) {
      throw `Bad constructor ${v.tag}; expected one of ${ctrs}`
   }
   return i == j
}

// Selectable projections
function val(x) {
   return x._1
}

function selState(x) {
   return x._2
}

const 𝕊_ctrs = ["None", "Primary", "Secondary"]

function 𝕊_isNone (v) {
   return isCtr(v, 0, 𝕊_ctrs)
}

function 𝕊_isPrimary (v) {
   return isCtr(v, 1, 𝕊_ctrs)
}

function 𝕊_isSecondary (v) {
   return isCtr(v, 2, 𝕊_ctrs)
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

// =================================================================
// End of duplicated prelude
// =================================================================

function prim (v) {
   if (isNaN(parseFloat(v._1))) {
      return v._1
   } else {
      return +parseFloat(v._1).toFixed(2)
   }
}

// any record type with only primitive fields -> Sel
function isUsed (r) {
   return Object.keys(r).some(k => k != indexKey && !Sel_isNone(selState(r[k]).persistent))
}

// Generic to all tables.
function drawTable_ (
   id,
   suffix,
   {
      title,   // String
      filter,  // Boolean
      table    // Homogeneous array of records with fields of primitive type
   },
   listener
) {
   return () => {
      const childId = id + '-' + suffix
      const div = d3.select('#' + id)

      indexKey = "__n"
      table = table.map((r, n) => { return {[ indexKey ]: n + 1, ...r} })

      const unfilteredLength = table.length
      div.selectAll('#' + childId).remove()
      if (filter) {
         table = table.filter(r => isUsed(r))
      }

      if (table.length > 0) {
         const HTMLtable = div
            .append('table')
            .attr('id', childId)

         const colNames = Object.keys(table[0]).sort()

         HTMLtable.append('caption')
            .text(title + ' (' + table.length + ' of ' + unfilteredLength + ')' )
            .attr('x', 0)
            .attr('y', 0)
            .attr('class', 'title-text table-caption')
            .attr('dominant-baseline', 'middle')
            .attr('text-anchor', 'left')

         const tableHead = HTMLtable.append('thead')
         tableHead
            .append('tr')
            .selectAll('th')
            .data(colNames)
            .enter()
            .append('th')
            .text(d => d == indexKey ? (filter ? "▸" : "▾" ) : d)

         const rows = HTMLtable
            .append('tbody')
            .selectAll('tr')
            .data(table)
            .enter()
            .append('tr')

         rows.selectAll('td')
            .data(d => colNames.map(
               k => { return { [ indexKey ]: d[indexKey], 'value': d[k], 'name': k } })
            )
            .enter()
            .append('td')
            .attr('data-th', d => d.name)
            .attr('class', d => d.name != indexKey && Sel_isPrimary(selState(d.value).persistent)
               ? 'cell-selected'
               : d.name != indexKey && Sel_isSecondary(selState(d.value).persistent)
                  ? 'cell-selected-secondary'
                  : 'cell-unselected')
            .text(d => d.name != indexKey ? prim(val(d.value)) : d.value)
            .on('mousedown', e => listener(e))

         sel = d3.select("th")
         sel.on("mouseover", e => console.log("TODO: toggle filter state persistently"))
      }
   }
}

export var drawTable = curry4(drawTable_)
