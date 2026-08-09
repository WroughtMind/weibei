import assert from 'node:assert/strict'

await import('../Sources/WeiBei/Resources/genui-math.js')

const { compileMathExpr, sampleExpr } = globalThis.WeiBeiSafeMath
const initial = sampleExpr('a * x + 1', -2, 2, 5, { a: 1 })
const changed = sampleExpr('a * x + 1', -2, 2, 5, { a: 3 })

assert.equal(initial.length, 5)
assert.equal(initial.at(-1)[1], 3)
assert.equal(changed.at(-1)[1], 7)
assert.equal(compileMathExpr('globalThis.process.exit()'), null)

console.log('WeiBei GenUI safe math self-check passed')
