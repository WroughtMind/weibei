import { mkdirSync } from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import type { StudyItemKind } from "../../shared/contracts";
import {
  COURSE_SEARCH_INDEX_FILE_NAME,
  COURSE_SEARCH_INDEX_SCHEMA,
} from "./search-index-schema";

export {
  COURSE_SEARCH_INDEX_FILE_NAME,
  COURSE_SEARCH_INDEX_SCHEMA,
} from "./search-index-schema";

const SQLITE_PAGE_BYTES = 4_096;
const MAXIMUM_SQLITE_BYTES = 768 * 1_024 * 1_024;
const MAXIMUM_PAGE_COUNT = MAXIMUM_SQLITE_BYTES / SQLITE_PAGE_BYTES;
const MAXIMUM_RESULTS = 6_000;
const DEFAULT_RESULT_LIMIT = 30;
const DEFAULT_RESULTS_PER_ITEM = 12;

const FILE_COLUMNS = [
  "item_id",
  "signature",
  "kind",
  "page_count",
  "processed_count",
  "is_complete",
  "chunk_count",
] as const;
const PROCESSED_PAGE_COLUMNS = [
  "item_id",
  "page_index",
  "extraction_kind",
] as const;
const NATIVE_ATTEMPTED_PAGE_COLUMNS = ["item_id", "page_index"] as const;
const CHUNK_COLUMNS = [
  "item_id",
  "sort_order",
  "location",
  "text",
  "terms",
] as const;
const CHUNK_INDEX_COLUMNS = ["chunk_rowid", "item_id", "sort_order"] as const;

export interface SearchIndexOpenOptions {
  dbPath: string;
}

export interface SearchTextChunk {
  text: string;
  location: string;
  /** Uses the array position when omitted. */
  sortOrder?: number;
}

export interface ProcessedPageInput {
  pageIndex: number;
  /** Swift values include text, text-partial, ocr, ocr-partial, empty and ocr-failed-*. */
  extractionKind: string;
}

export interface UpsertTextChunksInput {
  itemId: string;
  signature: string;
  kind: StudyItemKind;
  chunks: readonly SearchTextChunk[];
  /** Required for PDF inputs; non-PDF inputs default to one logical page. */
  pageCount?: number;
  processedPages?: readonly ProcessedPageInput[];
  nativeAttemptedPageIndexes?: readonly number[];
  /** Defaults to processedPages.length === pageCount for PDFs and true otherwise. */
  isComplete?: boolean;
}

export interface SearchCoverageUpdate {
  itemId: string;
  /** Rejects a late OCR update after the source changed. */
  signature: string;
  pageCount: number;
  processedPages: readonly ProcessedPageInput[];
  nativeAttemptedPageIndexes: readonly number[];
  isComplete?: boolean;
}

export interface SearchCoverage {
  itemId: string;
  signature: string;
  kind: StudyItemKind;
  totalPageCount: number;
  processedPageCount: number;
  indexedPageCount: number;
  chunkCount: number;
  isComplete: boolean;
  hasPartialExtraction: boolean;
  processedPages: readonly ProcessedPageInput[];
  nativeAttemptedPageIndexes: readonly number[];
  uncoveredPageIndexes: readonly number[];
  failedPageIndexes: readonly number[];
  failedPageReasons: Readonly<Record<number, string>>;
}

export interface SearchOptions {
  itemIds?: readonly string[];
  limit?: number;
}

export interface SearchHit {
  itemId: string;
  sortOrder: number;
  location: string;
  /** The original stored chunk. FTS ranks the parallel terms column, not this text column. */
  excerpt: string;
  /** Raw SQLite FTS5 BM25 score. Lower values are more relevant. */
  rank: number;
}

export interface Fts5Capability {
  available: boolean;
  sqliteVersion: string | null;
  error: string | null;
}

export interface SearchIndexDiagnostics {
  schema: typeof COURSE_SEARCH_INDEX_SCHEMA;
  dbPath: string;
  pageSize: number;
  maximumPageCount: number;
  autoVacuum: number;
  journalMode: string;
  synchronous: number;
  journalSizeLimit: number;
  walAutoCheckpoint: number;
  fts5: Fts5Capability;
}

export type SearchIndexErrorCode =
  | "closed"
  | "fts5-unavailable"
  | "invalid-input"
  | "schema-incompatible"
  | "stale-write";

export class SearchIndexError extends Error {
  constructor(
    readonly code: SearchIndexErrorCode,
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = "SearchIndexError";
  }
}

interface NormalizedDocument {
  itemId: string;
  signature: string;
  kind: StudyItemKind;
  chunks: readonly Required<SearchTextChunk>[];
  pageCount: number;
  processedPages: readonly ProcessedPageInput[];
  nativeAttemptedPageIndexes: readonly number[];
  processedCount: number;
  isComplete: boolean;
}

interface FileRow {
  item_id: string;
  signature: string;
  kind: string;
  page_count: number;
  processed_count: number;
  is_complete: number;
  chunk_count: number;
}

interface ProcessedPageRow {
  page_index: number;
  extraction_kind: string;
}

interface SearchRow {
  item_id: string;
  sort_order: number;
  location: string | null;
  text: string;
  rank: number;
}

interface TableInfoRow {
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
  pk: number;
}

/**
 * Rebuildable local FTS cache matching CourseDocumentSearchIndex's v3 SQLite layout.
 * All operations are synchronous and every public mutation is one IMMEDIATE transaction.
 */
export class SearchIndex {
  readonly dbPath: string;
  private closed = false;

  private constructor(
    private readonly database: Database.Database,
    dbPath: string,
  ) {
    this.dbPath = dbPath;
    this.configureConnection();
    const capability = probeFts5(this.database);
    if (!capability.available) {
      throw new SearchIndexError(
        "fts5-unavailable",
        `SQLite FTS5 is required: ${capability.error ?? "capability probe failed"}`,
      );
    }
    this.initializeSchema();
  }

  static open(options: SearchIndexOpenOptions | string): SearchIndex {
    const requestedPath = typeof options === "string" ? options : options.dbPath;
    if (typeof requestedPath !== "string" || requestedPath.trim().length === 0) {
      throw invalidInput("dbPath must be a non-empty string");
    }
    const dbPath = requestedPath === ":memory:"
      ? requestedPath
      : path.resolve(requestedPath);
    if (dbPath !== ":memory:") {
      mkdirSync(path.dirname(dbPath), { recursive: true });
    }
    const database = new Database(dbPath, { timeout: 2_000 });
    try {
      return new SearchIndex(database, dbPath);
    } catch (error) {
      try {
        database.close();
      } catch {
        // Preserve the opening error.
      }
      throw error;
    }
  }

  /** Performs a real create/insert/MATCH/bm25 probe on this connection. */
  selfCheckFts5(): Fts5Capability {
    this.ensureOpen();
    return probeFts5(this.database);
  }

  diagnostics(): SearchIndexDiagnostics {
    this.ensureOpen();
    return {
      schema: COURSE_SEARCH_INDEX_SCHEMA,
      dbPath: this.dbPath,
      pageSize: numberPragma(this.database, "page_size"),
      maximumPageCount: numberPragma(this.database, "max_page_count"),
      autoVacuum: numberPragma(this.database, "auto_vacuum"),
      journalMode: String(simplePragma(this.database, "journal_mode")).toLowerCase(),
      synchronous: numberPragma(this.database, "synchronous"),
      journalSizeLimit: numberPragma(this.database, "journal_size_limit"),
      walAutoCheckpoint: numberPragma(this.database, "wal_autocheckpoint"),
      fts5: probeFts5(this.database),
    };
  }

  upsertTextChunks(input: UpsertTextChunksInput): SearchCoverage {
    this.ensureOpen();
    const document = normalizeDocument(input);
    return this.writeTransaction(() => {
      this.upsertDocumentUnlocked(document);
      return this.requireCoverageUnlocked(document.itemId);
    });
  }

  /** Replaces PDF extraction coverage without disturbing already committed chunks. */
  updateCoverage(input: SearchCoverageUpdate): SearchCoverage {
    this.ensureOpen();
    const itemId = requiredString(input.itemId, "itemId");
    const signature = requiredString(input.signature, "signature");
    const existing = this.fileRow(itemId);
    if (!existing || existing.signature !== signature) {
      throw new SearchIndexError(
        "stale-write",
        `Coverage update rejected for stale or missing item ${itemId}`,
      );
    }
    if (existing.kind !== "pdf") {
      throw invalidInput("updateCoverage is only valid for PDF items");
    }
    if (input.pageCount !== existing.page_count) {
      throw new SearchIndexError(
        "stale-write",
        `PDF page count changed for ${itemId}; replace all chunks with upsertTextChunks`,
      );
    }
    const coverage = normalizeCoverage({
      kind: parseKind(existing.kind),
      pageCount: input.pageCount,
      processedPages: input.processedPages,
      nativeAttemptedPageIndexes: input.nativeAttemptedPageIndexes,
      isComplete: input.isComplete,
    });
    return this.writeTransaction(() => {
      const update = this.database.prepare(`
        UPDATE files
        SET processed_count = ?, is_complete = ?
        WHERE item_id = ? AND signature = ? AND kind = 'pdf' AND page_count = ?
      `).run(
        coverage.processedCount,
        coverage.isComplete ? 1 : 0,
        itemId,
        signature,
        coverage.pageCount,
      );
      if (update.changes !== 1) {
        throw new SearchIndexError(
          "stale-write",
          `Coverage update raced a source change for ${itemId}`,
        );
      }
      this.replaceCoverageRowsUnlocked(
        itemId,
        coverage.processedPages,
        coverage.nativeAttemptedPageIndexes,
      );
      return this.requireCoverageUnlocked(itemId);
    });
  }

  coverage(itemId: string): SearchCoverage | null {
    this.ensureOpen();
    const normalizedItemId = requiredString(itemId, "itemId");
    return this.readTransaction(() => this.coverageUnlocked(normalizedItemId));
  }

  private coverageUnlocked(normalizedItemId: string): SearchCoverage | null {
    const file = this.fileRow(normalizedItemId);
    if (!file) return null;

    const kind = parseKind(file.kind);
    const processedPages = this.database.prepare(`
      SELECT page_index, extraction_kind
      FROM processed_pages
      WHERE item_id = ?
      ORDER BY page_index
    `).all(normalizedItemId) as ProcessedPageRow[];
    const nativeAttemptedPageIndexes = (this.database.prepare(`
      SELECT page_index
      FROM native_attempted_pages
      WHERE item_id = ?
      ORDER BY page_index
    `).all(normalizedItemId) as Array<{ page_index: number }>).map(
      (row) => Number(row.page_index),
    );

    const normalizedProcessedPages = processedPages.map((page) => ({
      pageIndex: Number(page.page_index),
      extractionKind: page.extraction_kind,
    }));
    const indexedPageIndexes = new Set<number>();
    const failedPageIndexes: number[] = [];
    const failedPageReasons: Record<number, string> = {};
    let hasPartialExtraction = false;
    for (const page of normalizedProcessedPages) {
      if (page.extractionKind.includes("failed")) {
        hasPartialExtraction = true;
      }
      if (page.extractionKind.startsWith("ocr-failed-")) {
        failedPageIndexes.push(page.pageIndex);
        failedPageReasons[page.pageIndex] = page.extractionKind.slice(
          "ocr-failed-".length,
        ) || "unknown";
        hasPartialExtraction = true;
      } else if (page.extractionKind.endsWith("-partial")) {
        hasPartialExtraction = true;
      } else {
        indexedPageIndexes.add(page.pageIndex);
      }
    }

    const uncoveredPageIndexes: number[] = [];
    let indexedPageCount: number;
    if (kind === "pdf") {
      for (let pageIndex = 0; pageIndex < file.page_count; pageIndex += 1) {
        if (!indexedPageIndexes.has(pageIndex)) uncoveredPageIndexes.push(pageIndex);
      }
      indexedPageCount = indexedPageIndexes.size;
    } else {
      // Swift only publishes per-page coverage for PDFs. Keep non-PDF status useful
      // without falsely reporting its single logical page as uncovered.
      indexedPageCount = file.is_complete !== 0 ? file.page_count : 0;
    }

    return {
      itemId: file.item_id,
      signature: file.signature,
      kind,
      totalPageCount: Number(file.page_count),
      processedPageCount: Number(file.processed_count),
      indexedPageCount,
      chunkCount: Number(file.chunk_count),
      isComplete: file.is_complete !== 0,
      hasPartialExtraction,
      processedPages: normalizedProcessedPages,
      nativeAttemptedPageIndexes,
      uncoveredPageIndexes,
      failedPageIndexes,
      failedPageReasons,
    };
  }

  search(query: string, options: SearchOptions = {}): SearchHit[] {
    this.ensureOpen();
    if (typeof query !== "string") throw invalidInput("query must be a string");
    const terms = searchTerms(query).slice(0, 32);
    if (terms.length === 0) return [];

    const limit = boundedInteger(
      options.limit ?? DEFAULT_RESULT_LIMIT,
      "limit",
      1,
      MAXIMUM_RESULTS,
    );
    const itemIds = options.itemIds === undefined
      ? null
      : uniqueStrings(options.itemIds, "itemIds");
    if (itemIds?.length === 0) return [];

    const expression = terms
      .map((term) => `"${term.replaceAll('"', '""')}"`)
      .join(" OR ");
    const itemFilter = itemIds
      ? `AND item_id IN (${itemIds.map(() => "?").join(", ")})`
      : "";
    const rows = this.database.prepare(`
      WITH matches AS (
        SELECT item_id, sort_order, location, text, bm25(chunks) AS rank
        FROM chunks
        WHERE terms MATCH ? ${itemFilter}
      ), ranked AS (
        SELECT item_id, sort_order, location, text, rank,
          ROW_NUMBER() OVER (
            PARTITION BY item_id
            ORDER BY rank ASC, sort_order ASC
          ) AS row_number
        FROM matches
      )
      SELECT item_id, sort_order, location, text, rank
      FROM ranked
      WHERE row_number <= ?
      ORDER BY rank ASC, item_id ASC, sort_order ASC
      LIMIT ?
    `).all(
      expression,
      ...(itemIds ?? []),
      DEFAULT_RESULTS_PER_ITEM,
      limit,
    ) as SearchRow[];

    return rows.map((row) => ({
      itemId: row.item_id,
      sortOrder: Number(row.sort_order),
      location: row.location ?? "",
      excerpt: row.text,
      rank: Number(row.rank),
    }));
  }

  deleteItem(itemId: string): boolean {
    this.ensureOpen();
    const normalizedItemId = requiredString(itemId, "itemId");
    return this.writeTransaction(() => {
      const existed = this.hasIndexedContentUnlocked(normalizedItemId);
      this.deleteIndexedContentUnlocked(normalizedItemId);
      return existed;
    });
  }

  /** Drops and recreates the cache atomically, optionally seeding replacement documents. */
  rebuild(inputs: readonly UpsertTextChunksInput[] = []): SearchCoverage[] {
    this.ensureOpen();
    const documents = inputs.map(normalizeDocument);
    const itemIds = new Set<string>();
    for (const document of documents) {
      if (itemIds.has(document.itemId)) {
        throw invalidInput(`rebuild contains duplicate itemId ${document.itemId}`);
      }
      itemIds.add(document.itemId);
    }
    return this.writeTransaction(() => {
      this.dropSchemaUnlocked();
      this.createSchemaUnlocked();
      for (const document of documents) this.upsertDocumentUnlocked(document);
      if (!this.schemaIsCompatible()) {
        throw new SearchIndexError(
          "schema-incompatible",
          "Search index schema verification failed after rebuild",
        );
      }
      return documents.map((document) => this.requireCoverageUnlocked(document.itemId));
    });
  }

  close(): void {
    if (this.closed) return;
    try {
      this.database.pragma("wal_checkpoint(TRUNCATE)");
    } catch {
      // The index is a cache; checkpoint failure must not affect canonical data.
    }
    this.database.close();
    this.closed = true;
  }

  private configureConnection(): void {
    this.database.pragma(`busy_timeout = 2000`);
    this.database.pragma(`page_size = ${SQLITE_PAGE_BYTES}`);
    this.database.pragma(`max_page_count = ${MAXIMUM_PAGE_COUNT}`);
    this.database.pragma("auto_vacuum = INCREMENTAL");
    const journalMode = String(
      simplePragma(this.database, "journal_mode = WAL"),
    ).toLowerCase();
    if (this.dbPath !== ":memory:" && journalMode !== "wal") {
      throw new SearchIndexError(
        "schema-incompatible",
        `Search index requires WAL journal mode, received ${journalMode}`,
      );
    }
    this.database.pragma("synchronous = NORMAL");
    this.database.pragma("journal_size_limit = 67108864");
    this.database.pragma("wal_autocheckpoint = 256");
    if (numberPragma(this.database, "synchronous") !== 1) {
      throw new SearchIndexError(
        "schema-incompatible",
        "Search index could not enable synchronous=NORMAL",
      );
    }
  }

  private initializeSchema(): void {
    this.writeTransaction(() => {
      try {
        this.createSchemaUnlocked();
      } catch {
        this.dropSchemaUnlocked();
        this.createSchemaUnlocked();
      }
      if (!this.schemaIsCompatible()) {
        this.dropSchemaUnlocked();
        this.createSchemaUnlocked();
      }
      if (!this.schemaIsCompatible()) {
        throw new SearchIndexError(
          "schema-incompatible",
          "Search index v3 schema could not be created",
        );
      }
    });
  }

  private createSchemaUnlocked(): void {
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS files (
        item_id TEXT PRIMARY KEY,
        signature TEXT NOT NULL,
        kind TEXT NOT NULL,
        page_count INTEGER NOT NULL DEFAULT 0,
        processed_count INTEGER NOT NULL DEFAULT 0,
        is_complete INTEGER NOT NULL DEFAULT 0,
        chunk_count INTEGER NOT NULL DEFAULT 0
      )
    `);
    const fileColumns = this.tableColumns("files");
    if (!fileColumns.includes("chunk_count")) {
      this.database.exec(
        "ALTER TABLE files ADD COLUMN chunk_count INTEGER NOT NULL DEFAULT 0",
      );
    }
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS processed_pages (
        item_id TEXT NOT NULL,
        page_index INTEGER NOT NULL,
        extraction_kind TEXT NOT NULL,
        PRIMARY KEY (item_id, page_index)
      );
      CREATE TABLE IF NOT EXISTS native_attempted_pages (
        item_id TEXT NOT NULL,
        page_index INTEGER NOT NULL,
        PRIMARY KEY (item_id, page_index)
      );
      CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
        item_id UNINDEXED,
        sort_order UNINDEXED,
        location UNINDEXED,
        text UNINDEXED,
        terms,
        tokenize = 'unicode61 remove_diacritics 2'
      );
      CREATE TABLE IF NOT EXISTS chunk_index (
        chunk_rowid INTEGER PRIMARY KEY,
        item_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS chunk_index_item_sort
        ON chunk_index(item_id, sort_order);
      UPDATE processed_pages
      SET extraction_kind = 'ocr-failed-unknown'
      WHERE extraction_kind = 'failed';
    `);
  }

  private dropSchemaUnlocked(): void {
    this.database.exec(`
      DROP TABLE IF EXISTS chunks;
      DROP TABLE IF EXISTS chunk_index;
      DROP TABLE IF EXISTS processed_pages;
      DROP TABLE IF EXISTS native_attempted_pages;
      DROP TABLE IF EXISTS files;
    `);
  }

  private schemaIsCompatible(): boolean {
    if (!this.tableMatches(
      "files",
      FILE_COLUMNS,
      ["item_id"],
      [
        "signature",
        "kind",
        "page_count",
        "processed_count",
        "is_complete",
        "chunk_count",
      ],
      ["TEXT", "TEXT", "TEXT", "INTEGER", "INTEGER", "INTEGER", "INTEGER"],
      [null, null, null, "0", "0", "0", "0"],
    )) return false;
    if (!this.tableMatches(
      "processed_pages",
      PROCESSED_PAGE_COLUMNS,
      ["item_id", "page_index"],
      PROCESSED_PAGE_COLUMNS,
      ["TEXT", "INTEGER", "TEXT"],
      [null, null, null],
    )) return false;
    if (!this.tableMatches(
      "native_attempted_pages",
      NATIVE_ATTEMPTED_PAGE_COLUMNS,
      ["item_id", "page_index"],
      NATIVE_ATTEMPTED_PAGE_COLUMNS,
      ["TEXT", "INTEGER"],
      [null, null],
    )) return false;
    if (!this.tableMatches(
      "chunks",
      CHUNK_COLUMNS,
      [],
      [],
      ["", "", "", "", ""],
      [null, null, null, null, null],
    )) return false;
    if (!this.tableMatches(
      "chunk_index",
      CHUNK_INDEX_COLUMNS,
      ["chunk_rowid"],
      ["item_id", "sort_order"],
      ["INTEGER", "TEXT", "INTEGER"],
      [null, null, null],
    )) return false;
    const chunksSql = this.database.prepare(`
      SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'chunks'
    `).get() as { sql: string | null } | undefined;
    const normalizedSql = (chunksSql?.sql ?? "").toLowerCase().replace(/\s+/gu, " ");
    if (!normalizedSql.includes("using fts5")) return false;
    if (!normalizedSql.includes("unicode61 remove_diacritics 2")) return false;
    for (const column of ["item_id", "sort_order", "location", "text"]) {
      if (!normalizedSql.includes(`${column} unindexed`)) return false;
    }
    const index = this.database.prepare(`
      SELECT sql
      FROM sqlite_master
      WHERE type = 'index' AND name = 'chunk_index_item_sort'
    `).get() as { sql: string | null } | undefined;
    return /on\s+chunk_index\s*\(\s*item_id\s*,\s*sort_order\s*\)/iu
      .test(index?.sql ?? "");
  }

  private tableColumns(table: string): string[] {
    return this.tableInfo(table).map((row) => row.name);
  }

  private tableInfo(table: string): TableInfoRow[] {
    return this.database.prepare(`PRAGMA table_info(${table})`).all() as TableInfoRow[];
  }

  private tableMatches(
    table: string,
    columns: readonly string[],
    primaryKey: readonly string[],
    notNull: readonly string[],
    types: readonly string[],
    defaults: readonly (string | null)[],
  ): boolean {
    const info = this.tableInfo(table);
    if (!sameStrings(info.map((column) => column.name), columns)) return false;
    if (!sameStrings(
      info.map((column) => column.type.toUpperCase()),
      types,
    )) return false;
    if (
      info.length !== defaults.length
      || info.some((column, index) => column.dflt_value !== defaults[index])
    ) return false;
    const actualPrimaryKey = info
      .filter((column) => column.pk > 0)
      .sort((left, right) => left.pk - right.pk)
      .map((column) => column.name);
    if (!sameStrings(actualPrimaryKey, primaryKey)) return false;
    const requiredColumns = new Set(notNull);
    return info.every((column) => (
      !requiredColumns.has(column.name) || column.notnull === 1
    ));
  }

  private upsertDocumentUnlocked(document: NormalizedDocument): void {
    this.deleteIndexedContentUnlocked(document.itemId);
    const insertChunk = this.database.prepare(`
      INSERT INTO chunks (item_id, sort_order, location, text, terms)
      VALUES (?, ?, ?, ?, ?)
    `);
    const insertChunkIndex = this.database.prepare(`
      INSERT INTO chunk_index (chunk_rowid, item_id, sort_order)
      VALUES (?, ?, ?)
    `);
    for (const chunk of document.chunks) {
      const inserted = insertChunk.run(
        document.itemId,
        chunk.sortOrder,
        chunk.location,
        chunk.text,
        searchTerms(chunk.text).join(" "),
      );
      insertChunkIndex.run(
        inserted.lastInsertRowid,
        document.itemId,
        chunk.sortOrder,
      );
    }
    this.replaceCoverageRowsUnlocked(
      document.itemId,
      document.processedPages,
      document.nativeAttemptedPageIndexes,
    );
    this.database.prepare(`
      INSERT INTO files (
        item_id, signature, kind, page_count, processed_count, is_complete, chunk_count
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(
      document.itemId,
      document.signature,
      document.kind,
      document.pageCount,
      document.processedCount,
      document.isComplete ? 1 : 0,
      document.chunks.length,
    );
  }

  private replaceCoverageRowsUnlocked(
    itemId: string,
    processedPages: readonly ProcessedPageInput[],
    nativeAttemptedPageIndexes: readonly number[],
  ): void {
    this.database.prepare("DELETE FROM processed_pages WHERE item_id = ?").run(itemId);
    this.database.prepare(
      "DELETE FROM native_attempted_pages WHERE item_id = ?",
    ).run(itemId);
    const insertProcessedPage = this.database.prepare(`
      INSERT INTO processed_pages (item_id, page_index, extraction_kind)
      VALUES (?, ?, ?)
    `);
    for (const page of processedPages) {
      insertProcessedPage.run(itemId, page.pageIndex, page.extractionKind);
    }
    const insertNativeAttempt = this.database.prepare(`
      INSERT INTO native_attempted_pages (item_id, page_index)
      VALUES (?, ?)
    `);
    for (const pageIndex of nativeAttemptedPageIndexes) {
      insertNativeAttempt.run(itemId, pageIndex);
    }
  }

  private deleteIndexedContentUnlocked(itemId: string): void {
    this.database.prepare(`
      DELETE FROM chunks
      WHERE rowid IN (
        SELECT chunk_rowid FROM chunk_index WHERE item_id = ?
      )
    `).run(itemId);
    this.database.prepare("DELETE FROM chunk_index WHERE item_id = ?").run(itemId);
    this.database.prepare("DELETE FROM processed_pages WHERE item_id = ?").run(itemId);
    this.database.prepare(
      "DELETE FROM native_attempted_pages WHERE item_id = ?",
    ).run(itemId);
    this.database.prepare("DELETE FROM files WHERE item_id = ?").run(itemId);
  }

  private hasIndexedContentUnlocked(itemId: string): boolean {
    const row = this.database.prepare(`
      SELECT EXISTS(
        SELECT 1 FROM files WHERE item_id = ?
        UNION ALL SELECT 1 FROM processed_pages WHERE item_id = ?
        UNION ALL SELECT 1 FROM native_attempted_pages WHERE item_id = ?
        UNION ALL SELECT 1 FROM chunk_index WHERE item_id = ?
      ) AS found
    `).get(itemId, itemId, itemId, itemId) as { found: number };
    return row.found !== 0;
  }

  private fileRow(itemId: string): FileRow | null {
    return (this.database.prepare(`
      SELECT item_id, signature, kind, page_count, processed_count,
        is_complete, chunk_count
      FROM files
      WHERE item_id = ?
    `).get(itemId) as FileRow | undefined) ?? null;
  }

  private requireCoverageUnlocked(itemId: string): SearchCoverage {
    const coverage = this.coverageUnlocked(itemId);
    if (!coverage) {
      throw new SearchIndexError(
        "schema-incompatible",
        `Search index lost the file record for ${itemId}`,
      );
    }
    return coverage;
  }

  private writeTransaction<T>(body: () => T): T {
    this.database.exec("BEGIN IMMEDIATE");
    try {
      const result = body();
      this.database.exec("COMMIT");
      return result;
    } catch (error) {
      if (this.database.inTransaction) {
        try {
          this.database.exec("ROLLBACK");
        } catch {
          // Preserve the operation error.
        }
      }
      throw error;
    }
  }

  private readTransaction<T>(body: () => T): T {
    this.database.exec("BEGIN DEFERRED");
    try {
      const result = body();
      this.database.exec("COMMIT");
      return result;
    } catch (error) {
      if (this.database.inTransaction) {
        try {
          this.database.exec("ROLLBACK");
        } catch {
          // Preserve the read error.
        }
      }
      throw error;
    }
  }

  private ensureOpen(): void {
    if (this.closed) {
      throw new SearchIndexError("closed", "Search index is closed");
    }
  }
}

/** Standalone startup/package capability check using the linked SQLite library. */
export function checkFts5Capability(): Fts5Capability {
  let database: Database.Database | null = null;
  try {
    database = new Database(":memory:");
    return probeFts5(database);
  } catch (error) {
    return {
      available: false,
      sqliteVersion: null,
      error: errorMessage(error),
    };
  } finally {
    try {
      database?.close();
    } catch {
      // A failed probe is fully represented in the returned capability.
    }
  }
}

function probeFts5(database: Database.Database): Fts5Capability {
  let sqliteVersion: string | null = null;
  try {
    const version = database.prepare("SELECT sqlite_version() AS version").get() as {
      version: string;
    };
    sqliteVersion = version.version;
    database.exec("DROP TABLE IF EXISTS temp.__weibei_fts5_probe");
    database.exec(`
      CREATE VIRTUAL TABLE temp.__weibei_fts5_probe USING fts5(
        terms,
        tokenize = 'unicode61 remove_diacritics 2'
      );
      INSERT INTO temp.__weibei_fts5_probe (terms)
      VALUES ('weibei capability 流动性 café');
    `);
    const row = database.prepare(`
      SELECT bm25(__weibei_fts5_probe) AS rank
      FROM temp.__weibei_fts5_probe
      WHERE __weibei_fts5_probe MATCH '"weibei" OR "流动性" OR "cafe"'
    `).get() as { rank: number } | undefined;
    if (!row || !Number.isFinite(Number(row.rank))) {
      throw new Error("FTS5 MATCH/bm25 probe returned no finite rank");
    }
    return { available: true, sqliteVersion, error: null };
  } catch (error) {
    return { available: false, sqliteVersion, error: errorMessage(error) };
  } finally {
    try {
      database.exec("DROP TABLE IF EXISTS temp.__weibei_fts5_probe");
    } catch {
      // Keep the original probe result.
    }
  }
}

function normalizeDocument(input: UpsertTextChunksInput): NormalizedDocument {
  if (!input || typeof input !== "object") {
    throw invalidInput("upsert input must be an object");
  }
  const itemId = requiredString(input.itemId, "itemId");
  const signature = requiredString(input.signature, "signature");
  const kind = parseKind(input.kind);
  if (!Array.isArray(input.chunks)) throw invalidInput("chunks must be an array");
  const sortOrders = new Set<number>();
  const chunks = input.chunks.map((chunk, index) => {
    if (!chunk || typeof chunk !== "object") {
      throw invalidInput(`chunks[${index}] must be an object`);
    }
    if (typeof chunk.text !== "string" || chunk.text.length === 0) {
      throw invalidInput(`chunks[${index}].text must be non-empty`);
    }
    if (typeof chunk.location !== "string") {
      throw invalidInput(`chunks[${index}].location must be a string`);
    }
    const sortOrder = boundedInteger(
      chunk.sortOrder ?? index,
      `chunks[${index}].sortOrder`,
      0,
      Number.MAX_SAFE_INTEGER,
    );
    if (sortOrders.has(sortOrder)) {
      throw invalidInput(`chunks contains duplicate sortOrder ${sortOrder}`);
    }
    sortOrders.add(sortOrder);
    return { text: chunk.text, location: chunk.location, sortOrder };
  });

  if (kind === "pdf" && input.pageCount === undefined) {
    throw invalidInput("pageCount is required for PDF inputs");
  }
  const coverage = normalizeCoverage({
    kind,
    pageCount: input.pageCount ?? 1,
    processedPages: input.processedPages ?? [],
    nativeAttemptedPageIndexes: input.nativeAttemptedPageIndexes ?? [],
    isComplete: input.isComplete,
  });
  return { itemId, signature, kind, chunks, ...coverage };
}

function normalizeCoverage(input: {
  kind: StudyItemKind;
  pageCount: number;
  processedPages: readonly ProcessedPageInput[];
  nativeAttemptedPageIndexes: readonly number[];
  isComplete?: boolean;
}): Pick<
  NormalizedDocument,
  | "pageCount"
  | "processedPages"
  | "nativeAttemptedPageIndexes"
  | "processedCount"
  | "isComplete"
> {
  const pageCount = boundedInteger(input.pageCount, "pageCount", 0, 1_000_000);
  if (!Array.isArray(input.processedPages)) {
    throw invalidInput("processedPages must be an array");
  }
  if (!Array.isArray(input.nativeAttemptedPageIndexes)) {
    throw invalidInput("nativeAttemptedPageIndexes must be an array");
  }
  const processedIndexes = new Set<number>();
  const processedPages = input.processedPages.map((page, index) => {
    if (!page || typeof page !== "object") {
      throw invalidInput(`processedPages[${index}] must be an object`);
    }
    const pageIndex = boundedInteger(
      page.pageIndex,
      `processedPages[${index}].pageIndex`,
      0,
      Math.max(pageCount - 1, 0),
    );
    if (pageCount === 0) {
      throw invalidInput("processedPages must be empty when pageCount is zero");
    }
    if (processedIndexes.has(pageIndex)) {
      throw invalidInput(`processedPages contains duplicate pageIndex ${pageIndex}`);
    }
    processedIndexes.add(pageIndex);
    return {
      pageIndex,
      extractionKind: requiredString(
        page.extractionKind,
        `processedPages[${index}].extractionKind`,
      ),
    };
  });
  const nativeAttemptedPageIndexes = input.nativeAttemptedPageIndexes.map(
    (pageIndex, index) => boundedInteger(
      pageIndex,
      `nativeAttemptedPageIndexes[${index}]`,
      0,
      Math.max(pageCount - 1, 0),
    ),
  );
  if (pageCount === 0 && nativeAttemptedPageIndexes.length > 0) {
    throw invalidInput("nativeAttemptedPageIndexes must be empty when pageCount is zero");
  }
  if (new Set(nativeAttemptedPageIndexes).size !== nativeAttemptedPageIndexes.length) {
    throw invalidInput("nativeAttemptedPageIndexes contains duplicates");
  }

  const processedCount = input.kind === "pdf" || processedPages.length > 0
    ? processedPages.length
    : (input.isComplete ?? true) ? pageCount : 0;
  const defaultComplete = input.kind === "pdf"
    ? processedCount === pageCount
    : true;
  const isComplete = input.isComplete ?? defaultComplete;
  if (typeof isComplete !== "boolean") {
    throw invalidInput("isComplete must be a boolean");
  }
  if (input.kind === "pdf" && isComplete !== (processedCount === pageCount)) {
    throw invalidInput(
      "PDF isComplete must equal processedPages.length === pageCount",
    );
  }
  return {
    pageCount,
    processedPages: processedPages.sort((left, right) => left.pageIndex - right.pageIndex),
    nativeAttemptedPageIndexes: [...nativeAttemptedPageIndexes].sort((a, b) => a - b),
    processedCount,
    isComplete,
  };
}

function searchTerms(text: string): string[] {
  const lower = text.toLowerCase();
  const terms = lower
    .split(/[^\p{L}\p{N}_]+/u)
    .filter((term) => Array.from(term).length >= 2);
  let chineseRun = "";
  for (const scalar of lower) {
    const value = scalar.codePointAt(0) ?? 0;
    if (value >= 0x4e00 && value <= 0x9fff) {
      chineseRun += scalar;
    } else if (chineseRun.length > 0) {
      appendChineseTerms(chineseRun, terms);
      chineseRun = "";
    }
  }
  if (chineseRun.length > 0) appendChineseTerms(chineseRun, terms);
  return [...new Set(terms)];
}

function appendChineseTerms(run: string, terms: string[]): void {
  const characters = Array.from(run);
  if (characters.length <= 20) terms.push(run);
  for (let index = 0; index + 1 < characters.length; index += 1) {
    terms.push(characters[index] + characters[index + 1]);
  }
}

function parseKind(value: unknown): StudyItemKind {
  if (value === "html" || value === "pdf" || value === "markdown" || value === "text") {
    return value;
  }
  throw invalidInput(`Unsupported search item kind: ${String(value)}`);
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw invalidInput(`${name} must be a non-empty string`);
  }
  return value;
}

function uniqueStrings(values: readonly string[], name: string): string[] {
  if (!Array.isArray(values)) throw invalidInput(`${name} must be an array`);
  return [...new Set(values.map((value, index) => requiredString(value, `${name}[${index}]`)))];
}

function boundedInteger(
  value: unknown,
  name: string,
  minimum: number,
  maximum: number,
): number {
  if (
    typeof value !== "number"
    || !Number.isSafeInteger(value)
    || value < minimum
    || value > maximum
  ) {
    throw invalidInput(`${name} must be an integer from ${minimum} through ${maximum}`);
  }
  return value;
}

function invalidInput(message: string): SearchIndexError {
  return new SearchIndexError("invalid-input", message);
}

function sameStrings(
  actual: readonly string[],
  expected: readonly string[],
): boolean {
  return actual.length === expected.length
    && actual.every((value, index) => value === expected[index]);
}

function simplePragma(database: Database.Database, pragma: string): unknown {
  return database.pragma(pragma, { simple: true });
}

function numberPragma(database: Database.Database, pragma: string): number {
  return Number(simplePragma(database, pragma));
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
