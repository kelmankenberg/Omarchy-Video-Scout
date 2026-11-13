const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const path = require("node:path")

const context = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "../scroll-read.js"), "utf8"), context)
const rows = [{id: "first", bottom: 100}, {id: "second", bottom: 200}]
const ready = (pending, now) => Array.from(context.ready(pending, now))

// Crossing requires the entire card to be above the viewport for over a second.
let pending = context.advance({}, rows, 0, 99, 0)
assert.deepEqual(ready(pending, 2000), [])
pending = context.advance(pending, rows, 99, 100, 100)
assert.deepEqual(ready(pending, 1100), [])
assert.deepEqual(ready(pending, 1101), ["first"])

// Returning into view cancels the deadline; crossing again starts a fresh one.
pending = context.advance(pending, rows, 100, 90, 500)
assert.deepEqual(ready(pending, 2000), [])
pending = context.advance(pending, rows, 90, 110, 600)
assert.deepEqual(ready(pending, 1600), [])
assert.deepEqual(ready(pending, 1601), ["first"])

// Stationary cards that were already above the viewport are not marked.
assert.deepEqual(ready(context.advance({}, rows, 200, 200, 0), 2000), [])
pending = context.advance({}, rows, 0, 210, 100)
assert.deepEqual(ready(pending, 1101), ["first", "second"])

// Removing a row (read manually or a replaced list) drops its pending action.
pending = context.advance(pending, [rows[1]], 210, 210, 200)
assert.deepEqual(ready(pending, 1200), ["second"])
console.log("Scroll read tests passed.")
