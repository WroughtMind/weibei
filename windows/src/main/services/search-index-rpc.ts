import type {
  Fts5Capability,
  SearchCoverage,
  SearchCoverageUpdate,
  SearchHit,
  SearchIndexDiagnostics,
  SearchOptions,
  UpsertTextChunksInput,
} from "./search-index";

export const SEARCH_INDEX_RPC_PROTOCOL = "weibei.search-index" as const;
export const SEARCH_INDEX_RPC_VERSION = 1 as const;

export interface SearchIndexRpcMethods {
  open: {
    params: { dbPath: string };
    result: SearchIndexDiagnostics;
  };
  selfCheckFts5: {
    params: null;
    result: Fts5Capability;
  };
  diagnostics: {
    params: null;
    result: SearchIndexDiagnostics;
  };
  upsertTextChunks: {
    params: { input: UpsertTextChunksInput };
    result: SearchCoverage;
  };
  updateCoverage: {
    params: { input: SearchCoverageUpdate };
    result: SearchCoverage;
  };
  coverage: {
    params: { itemId: string };
    result: SearchCoverage | null;
  };
  search: {
    params: { query: string; options: SearchOptions };
    result: SearchHit[];
  };
  deleteItem: {
    params: { itemId: string };
    result: boolean;
  };
  rebuild: {
    params: { inputs: readonly UpsertTextChunksInput[] };
    result: SearchCoverage[];
  };
  close: {
    params: null;
    result: null;
  };
}

export type SearchIndexRpcMethod = keyof SearchIndexRpcMethods;
export type SearchIndexRpcParams<M extends SearchIndexRpcMethod> =
  SearchIndexRpcMethods[M]["params"];
export type SearchIndexRpcResult<M extends SearchIndexRpcMethod> =
  SearchIndexRpcMethods[M]["result"];

export type SearchIndexRpcRequestFor<M extends SearchIndexRpcMethod> = {
  protocol: typeof SEARCH_INDEX_RPC_PROTOCOL;
  version: typeof SEARCH_INDEX_RPC_VERSION;
  id: number;
  method: M;
  params: SearchIndexRpcParams<M>;
};

export type SearchIndexRpcRequest = {
  [M in SearchIndexRpcMethod]: SearchIndexRpcRequestFor<M>;
}[SearchIndexRpcMethod];

export interface SearchIndexRpcSuccess {
  protocol: typeof SEARCH_INDEX_RPC_PROTOCOL;
  version: typeof SEARCH_INDEX_RPC_VERSION;
  id: number;
  ok: true;
  result: unknown;
}

export interface SearchIndexRpcFailure {
  protocol: typeof SEARCH_INDEX_RPC_PROTOCOL;
  version: typeof SEARCH_INDEX_RPC_VERSION;
  id: number;
  ok: false;
  error: {
    code: string;
    message: string;
  };
}

export type SearchIndexRpcResponse = SearchIndexRpcSuccess | SearchIndexRpcFailure;

export function makeSearchIndexRpcRequest<M extends SearchIndexRpcMethod>(
  id: number,
  method: M,
  params: SearchIndexRpcParams<M>,
): SearchIndexRpcRequestFor<M> {
  return {
    protocol: SEARCH_INDEX_RPC_PROTOCOL,
    version: SEARCH_INDEX_RPC_VERSION,
    id,
    method,
    params,
  };
}

export function isSearchIndexRpcRequest(value: unknown): value is SearchIndexRpcRequest {
  if (!isRpcEnvelope(value) || typeof value.method !== "string") return false;
  switch (value.method) {
    case "open":
      return isRecord(value.params)
        && isBoundedString(value.params.dbPath, 32_767)
        && value.params.dbPath.length > 0
        && !value.params.dbPath.includes("\0");
    case "selfCheckFts5":
    case "diagnostics":
    case "close":
      return value.params === null;
    case "upsertTextChunks":
    case "updateCoverage":
      return isRecord(value.params) && isRecord(value.params.input);
    case "coverage":
    case "deleteItem":
      return isRecord(value.params)
        && isBoundedString(value.params.itemId, 1_024)
        && value.params.itemId.length > 0;
    case "search":
      return isRecord(value.params)
        && isBoundedString(value.params.query, 32_000)
        && isRecord(value.params.options);
    case "rebuild":
      return isRecord(value.params) && Array.isArray(value.params.inputs);
    default:
      return false;
  }
}

export function isSearchIndexRpcResponse(value: unknown): value is SearchIndexRpcResponse {
  if (!isRpcEnvelope(value) || typeof value.ok !== "boolean") return false;
  if (value.ok) return Object.hasOwn(value, "result");
  return isRecord(value.error)
    && isBoundedString(value.error.code, 128)
    && value.error.code.length > 0
    && isBoundedString(value.error.message, 2_048)
    && value.error.message.length > 0;
}

function isRpcEnvelope(value: unknown): value is Record<string, unknown> & { id: number } {
  return isRecord(value)
    && value.protocol === SEARCH_INDEX_RPC_PROTOCOL
    && value.version === SEARCH_INDEX_RPC_VERSION
    && Number.isSafeInteger(value.id)
    && (value.id as number) > 0;
}

function isBoundedString(value: unknown, maximumLength: number): value is string {
  return typeof value === "string" && value.length <= maximumLength;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
