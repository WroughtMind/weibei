import assert from 'node:assert/strict'
import process from 'node:process'

async function main() {
  // @ts-expect-error genui-math.js 是全局脚本运行时资源，无类型声明
  await import('../Sources/WeiBei/Resources/genui-math.js')

  const { compileMathExpr, sampleExpr } = (globalThis as any).WeiBeiSafeMath
  const initial = sampleExpr('a * x + 1', -2, 2, 5, { a: 1 })
  const changed = sampleExpr('a * x + 1', -2, 2, 5, { a: 3 })

  assert.equal(initial.length, 5)
  assert.equal(initial.at(-1)[1], 3)
  assert.equal(changed.at(-1)[1], 7)
  assert.equal(compileMathExpr('globalThis.process.exit()'), null)

  console.log('WeiBei GenUI safe math self-check passed')
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
