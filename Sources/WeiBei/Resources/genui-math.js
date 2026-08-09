/*
 * Safe math evaluator adapted from dsh-external/dsh-genui (MIT).
 * Parses a small mathematical grammar without eval or Function.
 */
(() => {
  'use strict';

  const constants = { pi: Math.PI, e: Math.E, tau: Math.PI * 2 };
  const functions = {
    sin: Math.sin, cos: Math.cos, tan: Math.tan,
    asin: Math.asin, acos: Math.acos, atan: Math.atan,
    sqrt: Math.sqrt, cbrt: Math.cbrt,
    exp: Math.exp, log: Math.log10, ln: Math.log,
    abs: Math.abs, floor: Math.floor, ceil: Math.ceil, round: Math.round,
    min: Math.min, max: Math.max, pow: Math.pow,
  };

  class Parser {
    constructor(source, variables) {
      this.source = source;
      this.variables = variables;
      this.index = 0;
    }

    parse() {
      const node = this.parseExpression();
      this.skipWhitespace();
      if (this.index < this.source.length) throw new Error('trailing input');
      return typeof node === 'number' ? () => node : node;
    }

    parseExpression() {
      let left = this.parseTerm();
      for (;;) {
        this.skipWhitespace();
        const operator = this.peek();
        if (operator !== '+' && operator !== '-') return left;
        this.index += 1;
        const right = this.parseTerm();
        const previous = left;
        left = operator === '+'
          ? x => this.value(previous, x) + this.value(right, x)
          : x => this.value(previous, x) - this.value(right, x);
      }
    }

    parseTerm() {
      let left = this.parseUnary();
      for (;;) {
        this.skipWhitespace();
        const operator = this.peek();
        if (!['*', '/', '%'].includes(operator)) return left;
        this.index += 1;
        const right = this.parseUnary();
        const previous = left;
        left = operator === '*'
          ? x => this.value(previous, x) * this.value(right, x)
          : operator === '/'
            ? x => this.value(previous, x) / this.value(right, x)
            : x => this.value(previous, x) % this.value(right, x);
      }
    }

    parseUnary() {
      this.skipWhitespace();
      const operator = this.peek();
      if (operator === '+' || operator === '-') {
        this.index += 1;
        const operand = this.parseUnary();
        return operator === '-' ? x => -this.value(operand, x) : x => this.value(operand, x);
      }
      return this.parsePower();
    }

    parsePower() {
      const base = this.parseAtom();
      this.skipWhitespace();
      if (this.peek() !== '^') return base;
      this.index += 1;
      const exponent = this.parsePower();
      return x => Math.pow(this.value(base, x), this.value(exponent, x));
    }

    parseAtom() {
      this.skipWhitespace();
      const character = this.peek();
      if (character === '(') {
        this.index += 1;
        const inner = this.parseExpression();
        this.skipWhitespace();
        if (this.peek() !== ')') throw new Error('expected )');
        this.index += 1;
        return inner;
      }
      if (character === '.' || /[0-9]/.test(character || '')) return this.parseNumber();
      if (/[a-zA-Z_]/.test(character || '')) return this.parseIdentifier();
      throw new Error('unexpected character');
    }

    parseNumber() {
      const match = this.source.slice(this.index).match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/);
      if (!match) throw new Error('invalid number');
      this.index += match[0].length;
      return Number(match[0]);
    }

    parseIdentifier() {
      const start = this.index;
      while (/[a-zA-Z0-9_]/.test(this.peek() || '')) this.index += 1;
      const name = this.source.slice(start, this.index);
      this.skipWhitespace();
      if (this.peek() === '(') {
        const fn = functions[name];
        if (!fn) throw new Error('unknown function');
        this.index += 1;
        const args = [];
        this.skipWhitespace();
        if (this.peek() === ')') {
          this.index += 1;
        } else {
          for (;;) {
            args.push(this.parseExpression());
            this.skipWhitespace();
            if (this.peek() === ',') {
              this.index += 1;
              continue;
            }
            if (this.peek() === ')') {
              this.index += 1;
              break;
            }
            throw new Error('expected , or )');
          }
        }
        return x => fn(...args.map(arg => this.value(arg, x)));
      }
      if (Object.hasOwn(constants, name)) return constants[name];
      if (name === 'x') return x => x;
      if (Object.hasOwn(this.variables, name)) {
        const captured = this.variables[name];
        return () => captured;
      }
      if (/^[a-z]$/.test(name)) return () => 1;
      throw new Error('unknown identifier');
    }

    value(node, x) {
      return typeof node === 'number' ? node : node(x);
    }

    skipWhitespace() {
      while (/\s/.test(this.peek() || '')) this.index += 1;
    }

    peek() {
      return this.source[this.index];
    }
  }

  function compileMathExpr(expression, options = {}) {
    try {
      const variables = { ...(options.variables || {}) };
      delete variables.x;
      return new Parser(String(expression).slice(0, 500), variables).parse();
    } catch {
      return null;
    }
  }

  function sampleExpr(expression, xMin, xMax, samples = 180, parameters = {}) {
    const evaluate = compileMathExpr(expression, { variables: parameters });
    if (!evaluate || !Number.isFinite(xMin) || !Number.isFinite(xMax) || xMax <= xMin || samples < 2) return [];
    const points = [];
    const step = (xMax - xMin) / (samples - 1);
    for (let index = 0; index < samples; index += 1) {
      const x = xMin + step * index;
      const y = evaluate(x);
      if (Number.isFinite(y)) points.push([x, y]);
    }
    return points;
  }

  globalThis.WeiBeiSafeMath = Object.freeze({ compileMathExpr, sampleExpr });
})();
