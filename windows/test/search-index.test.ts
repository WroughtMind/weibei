import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import Database from "better-sqlite3";
import {
  checkFts5Capability,
  SearchIndex,
  SearchIndexError,
  type UpsertTextChunksInput,
} from "../src/main/services/search-index";

interface TableInfoRow {
  name: string;
  notnull: number;
  dflt_value: string | null;
  pk: number;
}

async function withSearchIndex(
  body: (context: { index: SearchIndex; dbPath: string }) => void | Promise<void>,
): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-search-index-"));
  const dbPath = path.join(directory, "course-search-v3.sqlite3");
  const index = SearchIndex.open({ dbPath });
  try {
    await body({ index, dbPath });
  } finally {
    index.close();
    await rm(directory, { force: true, recursive: true });
  }
}

function tableInfo(database: Database.Database, table: string): TableInfoRow[] {
  return database.prepare(`PRAGMA table_info(${table})`).all() as TableInfoRow[];
}

function textDocument(
  itemId: string,
  signature: string,
  text: string,
  location = "正文",
): UpsertTextChunksInput {
  return {
    itemId,
    signature,
    kind: "text",
    chunks: [{ location, text }],
  };
}

test("FTS5 startup self-check exercises unicode61, MATCH and bm25", () => {
  const capability = checkFts5Capability();
  assert.equal(capability.available, true, capability.error ?? undefined);
  assert.match(capability.sqliteVersion ?? "", /^3\./u);

  const index = SearchIndex.open(":memory:");
  try {
    const connectionCapability = index.selfCheckFts5();
    assert.equal(connectionCapability.available, true, connectionCapability.error ?? undefined);
    assert.equal(connectionCapability.sqliteVersion, capability.sqliteVersion);
  } finally {
    index.close();
  }
});

test("creates the Swift v3 tables, tokenizer, index and durability pragmas", async () => {
  await withSearchIndex(({ index, dbPath }) => {
    const diagnostics = index.diagnostics();
    assert.equal(diagnostics.schema, "v3");
    assert.equal(diagnostics.dbPath, dbPath);
    assert.equal(diagnostics.pageSize, 4_096);
    assert.equal(diagnostics.maximumPageCount, 196_608);
    assert.equal(diagnostics.autoVacuum, 2);
    assert.equal(diagnostics.journalMode, "wal");
    assert.equal(diagnostics.synchronous, 1);
    assert.equal(diagnostics.journalSizeLimit, 67_108_864);
    assert.equal(diagnostics.walAutoCheckpoint, 256);

    const database = new Database(dbPath, { readonly: true });
    try {
      assert.deepEqual(
        tableInfo(database, "files").map((column) => column.name),
        [
          "item_id",
          "signature",
          "kind",
          "page_count",
          "processed_count",
          "is_complete",
          "chunk_count",
        ],
      );
      assert.deepEqual(
        tableInfo(database, "processed_pages").map((column) => column.name),
        ["item_id", "page_index", "extraction_kind"],
      );
      assert.deepEqual(
        tableInfo(database, "native_attempted_pages").map((column) => column.name),
        ["item_id", "page_index"],
      );
      assert.deepEqual(
        tableInfo(database, "chunks").map((column) => column.name),
        ["item_id", "sort_order", "location", "text", "terms"],
      );
      assert.deepEqual(
        tableInfo(database, "chunk_index").map((column) => column.name),
        ["chunk_rowid", "item_id", "sort_order"],
      );

      const processedPrimaryKey = tableInfo(database, "processed_pages")
        .filter((column) => column.pk > 0)
        .sort((left, right) => left.pk - right.pk)
        .map((column) => column.name);
      assert.deepEqual(processedPrimaryKey, ["item_id", "page_index"]);
      const nativePrimaryKey = tableInfo(database, "native_attempted_pages")
        .filter((column) => column.pk > 0)
        .sort((left, right) => left.pk - right.pk)
        .map((column) => column.name);
      assert.deepEqual(nativePrimaryKey, ["item_id", "page_index"]);

      const chunks = database.prepare(`
        SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'chunks'
      `).get() as { sql: string };
      assert.match(chunks.sql, /item_id\s+UNINDEXED/iu);
      assert.match(chunks.sql, /sort_order\s+UNINDEXED/iu);
      assert.match(chunks.sql, /location\s+UNINDEXED/iu);
      assert.match(chunks.sql, /text\s+UNINDEXED/iu);
      assert.match(
        chunks.sql,
        /tokenize\s*=\s*'unicode61 remove_diacritics 2'/iu,
      );
      const chunkIndex = database.prepare(`
        SELECT sql FROM sqlite_master
        WHERE type = 'index' AND name = 'chunk_index_item_sort'
      `).get() as { sql: string };
      assert.match(chunkIndex.sql, /chunk_index\s*\(item_id,\s*sort_order\)/iu);
    } finally {
      database.close();
    }
  });
});

test("upserts terms and returns raw BM25 hits with item, location and full chunk", async () => {
  await withSearchIndex(({ index }) => {
    const firstChunk = "# 货币理论\n流动性偏好解释了货币需求。Café markets remain liquid.";
    index.upsertTextChunks({
      itemId: "material-a",
      signature: "sig-a",
      kind: "markdown",
      chunks: [
        { sortOrder: 0, location: "货币理论", text: firstChunk },
        { sortOrder: 1, location: "期限结构", text: "预期理论与市场分割理论。" },
      ],
    });
    index.upsertTextChunks(textDocument(
      "material-b",
      "sig-b",
      "另一份 study study study material discusses liquidity.",
      "第二份",
    ));
    index.upsertTextChunks({
      itemId: "material-c",
      signature: "sig-c",
      kind: "text",
      chunks: Array.from({ length: 13 }, (_, sortOrder) => ({
        sortOrder,
        location: `chunk-${sortOrder}`,
        text: `study result ${sortOrder}`,
      })),
    });

    const chinese = index.search("动性");
    assert.equal(chinese.length, 1);
    assert.deepEqual(chinese[0], {
      itemId: "material-a",
      sortOrder: 0,
      location: "货币理论",
      excerpt: firstChunk,
      rank: chinese[0].rank,
    });
    assert.ok(Number.isFinite(chinese[0].rank));
    assert.ok(chinese[0].rank <= 0, "FTS5 BM25 is returned without reversing its sign");

    const accentFolded = index.search("cafe");
    assert.equal(accentFolded.length, 1);
    assert.equal(accentFolded[0].itemId, "material-a");

    assert.doesNotThrow(() => index.search('流动性 " OR * 偏好'));
    assert.equal(index.search("x").length, 0, "single Latin characters are not terms");

    const studyHits = index.search("study", {
      itemIds: ["material-b"],
      limit: 10,
    });
    assert.equal(studyHits.length, 1);
    assert.equal(studyHits[0].itemId, "material-b");
    assert.deepEqual(index.search("study", { itemIds: [] }), []);
    assert.equal(
      index.search("study", { itemIds: ["material-c"], limit: 20 }).length,
      12,
      "Swift v3 keeps at most twelve ranked chunks per item",
    );

    const all = index.search("theory 理论", { limit: 20 });
    for (let offset = 1; offset < all.length; offset += 1) {
      assert.ok(all[offset - 1].rank <= all[offset].rank);
    }
  });
});

test("upsert replaces stale chunks and source coverage in one transaction", async () => {
  await withSearchIndex(({ index, dbPath }) => {
    index.upsertTextChunks(textDocument(
      "replace-me",
      "revision-1",
      "旧内容包含流动性偏好。",
      "旧章节",
    ));
    assert.equal(index.search("流动性").length, 1);

    const replacement = index.upsertTextChunks(textDocument(
      "replace-me",
      "revision-2",
      "新内容只讨论期限结构。",
      "新章节",
    ));
    assert.equal(replacement.signature, "revision-2");
    assert.equal(replacement.chunkCount, 1);
    assert.equal(index.search("流动性").length, 0);
    assert.equal(index.search("期限结构")[0]?.location, "新章节");

    assert.throws(
      () => index.upsertTextChunks({
        itemId: "replace-me",
        signature: "revision-invalid",
        kind: "pdf",
        pageCount: 2,
        processedPages: [
          { pageIndex: 0, extractionKind: "text" },
          { pageIndex: 0, extractionKind: "ocr" },
        ],
        chunks: [{ location: "坏数据", text: "不应提交" }],
      }),
      (error: unknown) => error instanceof SearchIndexError
        && error.code === "invalid-input",
    );
    assert.equal(index.coverage("replace-me")?.signature, "revision-2");
    assert.equal(index.search("期限结构").length, 1);

    const faultInjector = new Database(dbPath);
    try {
      faultInjector.exec(`
        CREATE TRIGGER reject_test_chunk_index
        BEFORE INSERT ON chunk_index
        WHEN NEW.item_id = 'replace-me'
        BEGIN
          SELECT RAISE(ABORT, 'forced rollback');
        END
      `);
    } finally {
      faultInjector.close();
    }
    assert.throws(() => index.upsertTextChunks(textDocument(
      "replace-me",
      "revision-3",
      "事务失败时不得留下半份新索引。",
    )));
    assert.equal(index.coverage("replace-me")?.signature, "revision-2");
    assert.equal(index.search("期限结构").length, 1);
    assert.equal(index.search("半份新索引").length, 0);
  });
});

test("reports Swift PDF coverage including empty, partial and failed pages", async () => {
  await withSearchIndex(({ index }) => {
    const coverage = index.upsertTextChunks({
      itemId: "pdf-a",
      signature: "pdf-signature",
      kind: "pdf",
      pageCount: 4,
      processedPages: [
        { pageIndex: 0, extractionKind: "text" },
        { pageIndex: 1, extractionKind: "empty" },
        { pageIndex: 2, extractionKind: "text-partial" },
        { pageIndex: 3, extractionKind: "ocr-failed-timeout" },
      ],
      nativeAttemptedPageIndexes: [0, 1, 2, 3],
      isComplete: true,
      chunks: [
        { sortOrder: 0, location: "第 1 页", text: "第 1 页\n完整文本" },
        { sortOrder: 2_000, location: "第 3 页", text: "第 3 页\n部分文本" },
      ],
    });

    assert.equal(coverage.processedPageCount, 4);
    assert.equal(coverage.indexedPageCount, 2, "empty is a terminal indexed page");
    assert.equal(coverage.isComplete, true);
    assert.equal(coverage.hasPartialExtraction, true);
    assert.deepEqual(coverage.uncoveredPageIndexes, [2, 3]);
    assert.deepEqual(coverage.failedPageIndexes, [3]);
    assert.deepEqual(coverage.failedPageReasons, { 3: "timeout" });
    assert.deepEqual(coverage.nativeAttemptedPageIndexes, [0, 1, 2, 3]);

    assert.throws(
      () => index.updateCoverage({
        itemId: "pdf-a",
        signature: "pdf-signature",
        pageCount: 5,
        processedPages: [],
        nativeAttemptedPageIndexes: [],
        isComplete: false,
      }),
      (error: unknown) => error instanceof SearchIndexError
        && error.code === "stale-write",
    );
    assert.equal(index.search("完整文本")[0]?.location, "第 1 页");
    assert.equal(index.coverage("pdf-a")?.totalPageCount, 4);

    const retryState = index.updateCoverage({
      itemId: "pdf-a",
      signature: "pdf-signature",
      pageCount: 4,
      processedPages: [
        { pageIndex: 0, extractionKind: "text" },
        { pageIndex: 1, extractionKind: "empty" },
        { pageIndex: 2, extractionKind: "text-partial" },
      ],
      nativeAttemptedPageIndexes: [0, 1, 2],
      isComplete: false,
    });
    assert.equal(retryState.processedPageCount, 3);
    assert.equal(retryState.isComplete, false);
    assert.deepEqual(retryState.uncoveredPageIndexes, [2, 3]);
    assert.deepEqual(retryState.failedPageIndexes, []);

    assert.throws(
      () => index.updateCoverage({
        itemId: "pdf-a",
        signature: "old-signature",
        pageCount: 4,
        processedPages: [],
        nativeAttemptedPageIndexes: [],
        isComplete: false,
      }),
      (error: unknown) => error instanceof SearchIndexError
        && error.code === "stale-write",
    );
    assert.equal(index.coverage("pdf-a")?.processedPageCount, 3);
  });
});

test("delete removes all v3 rows and rebuild atomically replaces the cache", async () => {
  await withSearchIndex(({ index, dbPath }) => {
    index.upsertTextChunks(textDocument("one", "sig-1", "alpha searchable"));
    index.upsertTextChunks(textDocument("two", "sig-2", "beta searchable"));

    assert.equal(index.deleteItem("one"), true);
    assert.equal(index.deleteItem("one"), false);
    assert.equal(index.coverage("one"), null);
    assert.deepEqual(index.search("alpha"), []);

    assert.throws(
      () => index.rebuild([
        textDocument("duplicate", "sig-a", "first duplicate"),
        textDocument("duplicate", "sig-b", "second duplicate"),
      ]),
      (error: unknown) => error instanceof SearchIndexError
        && error.code === "invalid-input",
    );
    assert.equal(index.search("beta").length, 1, "failed rebuild preserves old cache");

    const rebuilt = index.rebuild([
      textDocument("three", "sig-3", "gamma rebuilt content", "重建章节"),
    ]);
    assert.equal(rebuilt.length, 1);
    assert.equal(index.coverage("two"), null);
    assert.equal(index.search("beta").length, 0);
    assert.equal(index.search("gamma")[0]?.itemId, "three");

    index.close();
    const reopened = SearchIndex.open(dbPath);
    try {
      assert.equal(reopened.search("gamma")[0]?.location, "重建章节");
      assert.equal(reopened.coverage("three")?.signature, "sig-3");
      reopened.deleteItem("three");
    } finally {
      reopened.close();
    }

    const database = new Database(dbPath, { readonly: true });
    try {
      for (const table of [
        "files",
        "processed_pages",
        "native_attempted_pages",
        "chunks",
        "chunk_index",
      ]) {
        const row = database.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get() as {
          count: number;
        };
        assert.equal(row.count, 0, `${table} retained deleted rows`);
      }
    } finally {
      database.close();
    }
  });
});

test("an incompatible cache schema is discarded because the index is rebuildable", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-search-legacy-"));
  const dbPath = path.join(directory, "course-search-v3.sqlite3");
  try {
    const incompatible = new Database(dbPath);
    incompatible.exec(`
      CREATE TABLE files (
        item_id TEXT,
        signature TEXT,
        kind TEXT,
        page_count INTEGER,
        processed_count INTEGER,
        is_complete INTEGER,
        chunk_count INTEGER
      )
    `);
    incompatible.prepare("INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?)").run(
      "stale",
      "old-signature",
      "text",
      1,
      1,
      1,
      0,
    );
    incompatible.close();

    const index = SearchIndex.open(dbPath);
    try {
      assert.equal(index.coverage("stale"), null);
      const verification = new Database(dbPath, { readonly: true });
      try {
        assert.deepEqual(
          tableInfo(verification, "files").map((column) => column.name),
          [
            "item_id",
            "signature",
            "kind",
            "page_count",
            "processed_count",
            "is_complete",
            "chunk_count",
          ],
        );
      } finally {
        verification.close();
      }
      index.upsertTextChunks(textDocument("fresh", "sig", "recovered index"));
      assert.equal(index.search("recovered")[0]?.itemId, "fresh");
    } finally {
      index.close();
    }
  } finally {
    await rm(directory, { force: true, recursive: true });
  }
});
