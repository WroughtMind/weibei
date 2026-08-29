import { Buffer } from "node:buffer";

/**
 * Foundation's reference date is 2001-01-01T00:00:00Z. JSONEncoder's default
 * Date strategy writes seconds relative to this instant (not Unix seconds and
 * not an ISO-8601 string).
 */
export const SWIFT_REFERENCE_DATE_UNIX_MILLISECONDS = 978_307_200_000;

export type SwiftJSONPrimitive = null | boolean | string | number | bigint;
export type SwiftJSONValue =
  | SwiftJSONPrimitive
  | SwiftJSONArray
  | SwiftJSONObject;
export interface SwiftJSONArray extends Array<SwiftJSONValue> {}
export interface SwiftJSONObject {
  [key: string]: SwiftJSONValue | undefined;
}

/** Minimal structural contract used by lossless-json's LosslessNumber. */
export interface LosslessNumberLike {
  readonly isLosslessNumber: true;
  readonly value?: string;
  toString(): string;
}

/**
 * An explicit JSON number token for callers which need to retain a decimal's
 * spelling. Persisted UInt64/Int64 values normally decode to bigint instead.
 */
export class SwiftJSONNumber implements LosslessNumberLike {
  readonly isLosslessNumber = true as const;

  constructor(readonly value: string) {
    if (!isJSONNumberToken(value)) {
      throw new TypeError(`Invalid JSON number token: ${value}`);
    }
  }

  toString(): string {
    return this.value;
  }
}

export interface SwiftStringifyOptions {
  /** Equivalent to JSON.stringify's space argument, capped at ten chars. */
  space?: number | string;
  /** Course-state hashing uses sorted keys; workspace snapshots do not. */
  sortKeys?: boolean;
  /** Workspace files conventionally end in a newline. */
  trailingNewline?: boolean;
}

export interface PersistedWorkspaceRecord extends SwiftJSONObject {
  importedItems: SwiftJSONArray;
  notesByItemID: SwiftJSONObject;
}

export function swiftReferenceSecondsFromDate(date: Date): number {
  const unixMilliseconds = date.getTime();
  if (!Number.isFinite(unixMilliseconds)) {
    throw new RangeError("Cannot encode an invalid Date");
  }
  return (unixMilliseconds - SWIFT_REFERENCE_DATE_UNIX_MILLISECONDS) / 1_000;
}

export function dateFromSwiftReferenceSeconds(
  seconds: number | bigint | SwiftJSONNumber | LosslessNumberLike,
): Date {
  const numericSeconds = numberFromJSONNumber(seconds);
  const unixMilliseconds =
    numericSeconds * 1_000 + SWIFT_REFERENCE_DATE_UNIX_MILLISECONDS;
  if (!Number.isFinite(unixMilliseconds)) {
    throw new RangeError("Swift Date is outside JavaScript's supported range");
  }
  const result = new Date(unixMilliseconds);
  if (!Number.isFinite(result.getTime())) {
    throw new RangeError("Swift Date is outside JavaScript's supported range");
  }
  return result;
}

export const encodeSwiftDate = swiftReferenceSecondsFromDate;
export const decodeSwiftDate = dateFromSwiftReferenceSeconds;

export function encodeSwiftData(data: Uint8Array): string {
  return Buffer.from(data.buffer, data.byteOffset, data.byteLength).toString(
    "base64",
  );
}

export function decodeSwiftData(encoded: string): Uint8Array {
  if (!isCanonicalBase64(encoded)) {
    throw new TypeError("Invalid Swift Data base64 value");
  }
  return new Uint8Array(Buffer.from(encoded, "base64"));
}

/**
 * Parse Codable JSON without rounding integer tokens. Integers inside the safe
 * JS range remain numbers; wider Int64/UInt64 tokens become bigint. Bigints are
 * written back as unquoted JSON number tokens by stringifySwiftJSON.
 */
export function parseSwiftJSON(source: string): SwiftJSONValue {
  return new SwiftJSONParser(source).parse();
}

export const parseSwiftCodableJSON = parseSwiftJSON;

/**
 * JSON.stringify-compatible encoder with three Codable additions:
 * - bigint and LosslessNumber-like values are emitted as number tokens;
 * - Date is emitted using Swift's 2001 reference epoch;
 * - Uint8Array/Buffer is emitted as Swift Data's base64 string.
 */
export function stringifySwiftJSON(
  value: unknown,
  options: SwiftStringifyOptions = {},
): string {
  const gap = stringifyGap(options.space);
  const stack = new Set<object>();
  const encoded = encodeValue(value, {
    depth: 0,
    gap,
    sortKeys: options.sortKeys ?? false,
    stack,
    arrayElement: false,
  });
  if (encoded === undefined) {
    throw new TypeError("The root value is not representable as JSON");
  }
  return encoded + (options.trailingNewline ? "\n" : "");
}

export const stringifySwiftCodableJSON = stringifySwiftJSON;

/** Decode while retaining every unknown key and unknown raw-string value. */
export function decodePersistedWorkspace(
  source: string | Uint8Array,
): PersistedWorkspaceRecord {
  const text =
    typeof source === "string"
      ? source
      : new TextDecoder("utf-8", { fatal: true }).decode(source);
  const decoded = parseSwiftJSON(text);
  if (!isJSONObject(decoded)) {
    throw new TypeError("workspace.json must contain a JSON object");
  }
  if (!Array.isArray(decoded.importedItems)) {
    throw new TypeError("workspace.json importedItems must be an array");
  }
  if (!isJSONObject(decoded.notesByItemID)) {
    throw new TypeError("workspace.json notesByItemID must be an object");
  }
  for (const draft of Object.values(decoded.notesByItemID)) {
    if (typeof draft !== "string") {
      throw new TypeError("workspace.json note drafts must be strings");
    }
  }
  return decoded as PersistedWorkspaceRecord;
}

export function encodePersistedWorkspace(
  workspace: PersistedWorkspaceRecord,
  options: SwiftStringifyOptions = {},
): string {
  validatePersistedWorkspace(workspace);
  return stringifySwiftJSON(workspace, options);
}

export function isJSONObject(value: unknown): value is SwiftJSONObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function isLosslessNumberLike(
  value: unknown,
): value is LosslessNumberLike {
  if (value === null || typeof value !== "object") return false;
  const candidate = value as Partial<LosslessNumberLike>;
  return (
    candidate.isLosslessNumber === true &&
    typeof candidate.toString === "function" &&
    isJSONNumberToken(candidate.toString())
  );
}

export function isJSONNumberToken(value: string): boolean {
  return /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(value);
}

function validatePersistedWorkspace(
  workspace: PersistedWorkspaceRecord,
): void {
  if (!isJSONObject(workspace)) {
    throw new TypeError("workspace.json must contain a JSON object");
  }
  if (!Array.isArray(workspace.importedItems)) {
    throw new TypeError("workspace.json importedItems must be an array");
  }
  if (!isJSONObject(workspace.notesByItemID)) {
    throw new TypeError("workspace.json notesByItemID must be an object");
  }
  for (const draft of Object.values(workspace.notesByItemID)) {
    if (typeof draft !== "string") {
      throw new TypeError("workspace.json note drafts must be strings");
    }
  }
}

function numberFromJSONNumber(
  value: number | bigint | SwiftJSONNumber | LosslessNumberLike,
): number {
  const result =
    typeof value === "number"
      ? value
      : typeof value === "bigint"
        ? Number(value)
        : Number(value.toString());
  if (!Number.isFinite(result)) {
    throw new RangeError("JSON number is outside JavaScript's supported range");
  }
  return result;
}

function isCanonicalBase64(value: string): boolean {
  if (value.length === 0) return true;
  if (value.length % 4 !== 0) return false;
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    return false;
  }
  return Buffer.from(value, "base64").toString("base64") === value;
}

interface EncodingContext {
  depth: number;
  gap: string;
  sortKeys: boolean;
  stack: Set<object>;
  arrayElement: boolean;
}

function encodeValue(
  value: unknown,
  context: EncodingContext,
): string | undefined {
  if (value === null) return "null";
  switch (typeof value) {
    case "string":
      return JSON.stringify(value);
    case "boolean":
      return value ? "true" : "false";
    case "number":
      return Number.isFinite(value) ? JSON.stringify(value) : "null";
    case "bigint":
      return value.toString(10);
    case "undefined":
    case "function":
    case "symbol":
      return context.arrayElement ? "null" : undefined;
    case "object":
      break;
  }

  if (value instanceof Date) {
    return String(swiftReferenceSecondsFromDate(value));
  }
  if (value instanceof Uint8Array) {
    return JSON.stringify(encodeSwiftData(value));
  }
  if (isLosslessNumberLike(value)) {
    return value.toString();
  }

  if (context.stack.has(value)) {
    throw new TypeError("Converting circular structure to JSON");
  }
  context.stack.add(value);
  try {
    if (Array.isArray(value)) {
      const values = value.map((entry) =>
        encodeValue(entry, {
          ...context,
          depth: context.depth + 1,
          arrayElement: true,
        }),
      );
      return formatCollection("[", "]", values as string[], context);
    }

    const record = value as Record<string, unknown>;
    const keys = Object.keys(record);
    if (context.sortKeys) keys.sort();
    const entries: Array<[string, string]> = [];
    for (const key of keys) {
      const encoded = encodeValue(record[key], {
        ...context,
        depth: context.depth + 1,
        arrayElement: false,
      });
      if (encoded !== undefined) entries.push([JSON.stringify(key), encoded]);
    }
    return formatObject(entries, context);
  } finally {
    context.stack.delete(value);
  }
}

function formatCollection(
  open: string,
  close: string,
  entries: string[],
  context: EncodingContext,
): string {
  if (entries.length === 0) return open + close;
  if (!context.gap) return `${open}${entries.join(",")}${close}`;
  const childIndent = context.gap.repeat(context.depth + 1);
  const ownIndent = context.gap.repeat(context.depth);
  return `${open}\n${childIndent}${entries.join(`,\n${childIndent}`)}\n${ownIndent}${close}`;
}

function formatObject(
  entries: Array<[string, string]>,
  context: EncodingContext,
): string {
  if (entries.length === 0) return "{}";
  if (!context.gap) {
    return `{${entries.map(([key, value]) => `${key}:${value}`).join(",")}}`;
  }
  const childIndent = context.gap.repeat(context.depth + 1);
  const ownIndent = context.gap.repeat(context.depth);
  return `{\n${childIndent}${entries
    .map(([key, value]) => `${key}: ${value}`)
    .join(`,\n${childIndent}`)}\n${ownIndent}}`;
}

function stringifyGap(space: number | string | undefined): string {
  if (typeof space === "number") {
    return " ".repeat(Math.max(0, Math.min(10, Math.trunc(space))));
  }
  if (typeof space === "string") return space.slice(0, 10);
  return "";
}

class SwiftJSONParser {
  private position = 0;
  private depth = 0;

  constructor(private readonly source: string) {}

  parse(): SwiftJSONValue {
    this.skipWhitespace();
    const value = this.parseValue();
    this.skipWhitespace();
    if (this.position !== this.source.length) this.fail("Unexpected token");
    return value;
  }

  private parseValue(): SwiftJSONValue {
    if (this.depth > 512) this.fail("JSON nesting exceeds 512 levels");
    const token = this.source[this.position];
    switch (token) {
      case "{":
        return this.withDepth(() => this.parseObject());
      case "[":
        return this.withDepth(() => this.parseArray());
      case '"':
        return this.parseString();
      case "t":
        this.consumeKeyword("true");
        return true;
      case "f":
        this.consumeKeyword("false");
        return false;
      case "n":
        this.consumeKeyword("null");
        return null;
      default:
        if (token === "-" || (token >= "0" && token <= "9")) {
          return this.parseNumber();
        }
        return this.fail("Expected a JSON value");
    }
  }

  private parseObject(): SwiftJSONObject {
    const result: SwiftJSONObject = {};
    this.position += 1;
    this.skipWhitespace();
    if (this.source[this.position] === "}") {
      this.position += 1;
      return result;
    }
    while (true) {
      if (this.source[this.position] !== '"') this.fail("Expected object key");
      const key = this.parseString();
      this.skipWhitespace();
      if (this.source[this.position] !== ":") this.fail("Expected ':'");
      this.position += 1;
      this.skipWhitespace();
      const value = this.parseValue();
      Object.defineProperty(result, key, {
        value,
        enumerable: true,
        configurable: true,
        writable: true,
      });
      this.skipWhitespace();
      const delimiter = this.source[this.position];
      if (delimiter === "}") {
        this.position += 1;
        return result;
      }
      if (delimiter !== ",") this.fail("Expected ',' or '}'");
      this.position += 1;
      this.skipWhitespace();
    }
  }

  private parseArray(): SwiftJSONArray {
    const result: SwiftJSONArray = [];
    this.position += 1;
    this.skipWhitespace();
    if (this.source[this.position] === "]") {
      this.position += 1;
      return result;
    }
    while (true) {
      result.push(this.parseValue());
      this.skipWhitespace();
      const delimiter = this.source[this.position];
      if (delimiter === "]") {
        this.position += 1;
        return result;
      }
      if (delimiter !== ",") this.fail("Expected ',' or ']'");
      this.position += 1;
      this.skipWhitespace();
    }
  }

  private parseString(): string {
    const start = this.position;
    this.position += 1;
    let escaped = false;
    while (this.position < this.source.length) {
      const character = this.source[this.position];
      if (!escaped && character === '"') {
        this.position += 1;
        const token = this.source.slice(start, this.position);
        try {
          return JSON.parse(token) as string;
        } catch {
          return this.fail("Invalid JSON string");
        }
      }
      if (!escaped && character.charCodeAt(0) < 0x20) {
        this.fail("Unescaped control character in string");
      }
      if (!escaped && character === "\\") {
        escaped = true;
      } else {
        escaped = false;
      }
      this.position += 1;
    }
    return this.fail("Unterminated JSON string");
  }

  private parseNumber(): number | bigint {
    const remainder = this.source.slice(this.position);
    const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/.exec(remainder);
    if (!match) return this.fail("Invalid JSON number");
    const token = match[0];
    this.position += token.length;
    if (!token.includes(".") && !/[eE]/.test(token)) {
      if (token === "-0") return -0;
      const integer = BigInt(token);
      if (
        integer <= BigInt(Number.MAX_SAFE_INTEGER) &&
        integer >= BigInt(Number.MIN_SAFE_INTEGER)
      ) {
        return Number(integer);
      }
      return integer;
    }
    const number = Number(token);
    if (!Number.isFinite(number)) this.fail("JSON number is out of range");
    return number;
  }

  private consumeKeyword(keyword: string): void {
    if (this.source.slice(this.position, this.position + keyword.length) !== keyword) {
      this.fail(`Expected '${keyword}'`);
    }
    this.position += keyword.length;
  }

  private skipWhitespace(): void {
    while (/\s/.test(this.source[this.position] ?? "") && this.position < this.source.length) {
      const character = this.source[this.position];
      if (character !== " " && character !== "\t" && character !== "\n" && character !== "\r") {
        this.fail("Invalid JSON whitespace");
      }
      this.position += 1;
    }
  }

  private withDepth<T>(operation: () => T): T {
    this.depth += 1;
    try {
      return operation();
    } finally {
      this.depth -= 1;
    }
  }

  private fail(message: string): never {
    throw new SyntaxError(`${message} at position ${this.position}`);
  }
}
