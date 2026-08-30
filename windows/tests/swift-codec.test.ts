import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { sha256 } from "../src/main/services/file-utils";
import {
  SWIFT_REFERENCE_DATE_UNIX_MILLISECONDS,
  SwiftJSONNumber,
  dateFromSwiftReferenceSeconds,
  decodePersistedWorkspace,
  decodeSwiftData,
  encodePersistedWorkspace,
  encodeSwiftData,
  parseSwiftJSON,
  stringifySwiftJSON,
  swiftReferenceSecondsFromDate,
  type PersistedWorkspaceRecord,
  type SwiftJSONObject,
} from "../src/main/services/swift-codec";
import { WorkspacePersistence } from "../src/main/services/workspace-persistence";

test("Swift Date uses the 2001 Foundation reference epoch", () => {
  assert.equal(
    swiftReferenceSecondsFromDate(new Date("2001-01-01T00:00:00.000Z")),
    0,
  );
  assert.equal(
    swiftReferenceSecondsFromDate(new Date("1970-01-01T00:00:00.000Z")),
    -978_307_200,
  );
  assert.equal(
    swiftReferenceSecondsFromDate(new Date("2001-01-01T00:00:00.125Z")),
    0.125,
  );
  assert.equal(
    dateFromSwiftReferenceSeconds(-978_307_200).toISOString(),
    "1970-01-01T00:00:00.000Z",
  );
  assert.equal(
    dateFromSwiftReferenceSeconds(0).getTime(),
    SWIFT_REFERENCE_DATE_UNIX_MILLISECONDS,
  );
});

test("wide Swift integers round-trip as unquoted bigint number tokens", () => {
  const maximumUInt64 = 18_446_744_073_709_551_615n;
  const minimumInt64 = -9_223_372_036_854_775_808n;
  const decoded = parseSwiftJSON(
    `{"revision":${maximumUInt64},"birth":${minimumInt64},"safe":42}`,
  ) as SwiftJSONObject;
  assert.equal(decoded.revision, maximumUInt64);
  assert.equal(decoded.birth, minimumInt64);
  assert.equal(decoded.safe, 42);

  const encoded = stringifySwiftJSON(decoded);
  assert.equal(
    encoded,
    `{"revision":${maximumUInt64},"birth":${minimumInt64},"safe":42}`,
  );
  assert.doesNotMatch(encoded, /"18446744073709551615"/);
});

test("lossless-json compatible number objects are emitted as number tokens", () => {
  const losslessLike = {
    isLosslessNumber: true as const,
    value: "18446744073709551615",
    toString() {
      return this.value;
    },
  };
  assert.equal(stringifySwiftJSON({ value: losslessLike }), '{"value":18446744073709551615}');
  assert.equal(
    stringifySwiftJSON({ decimal: new SwiftJSONNumber("1.2300") }),
    '{"decimal":1.2300}',
  );
});

test("unknown workspace keys and unknown preference raw values survive", () => {
  const source = JSON.stringify({
    importedItems: [],
    notesByItemID: {},
    appearanceModeRaw: "future-glass",
    interfaceLanguageRaw: "future-language",
    interfaceTextScaleRaw: "scale173",
    futureTopLevel: {
      futureAssociatedEnum: { futureCase: { _0: "opaque" } },
    },
  });
  const decoded = decodePersistedWorkspace(source);
  const redecoded = decodePersistedWorkspace(
    encodePersistedWorkspace(decoded),
  );
  assert.deepEqual(redecoded, decoded);
  assert.equal(redecoded.interfaceTextScaleRaw, "scale173");
  assert.deepEqual(redecoded.futureTopLevel, decoded.futureTopLevel);
});

test("Date and Data receive Swift Codable encodings", () => {
  const bytes = Uint8Array.from([0, 1, 2, 253, 254, 255]);
  const encodedData = encodeSwiftData(bytes);
  assert.equal(encodedData, "AAEC/f7/");
  assert.deepEqual(decodeSwiftData(encodedData), bytes);
  assert.equal(
    stringifySwiftJSON({
      createdAt: new Date("2001-01-01T00:00:01.500Z"),
      bookmark: bytes,
    }),
    '{"createdAt":1.5,"bookmark":"AAEC/f7/"}',
  );
});

test("invalid workspace cores and malformed JSON are rejected", () => {
  assert.throws(() => decodePersistedWorkspace("{}"), /importedItems/);
  assert.throws(
    () => decodePersistedWorkspace('{"importedItems":[],"notesByItemID":{"x":4}}'),
    /drafts must be strings/,
  );
  assert.throws(() => parseSwiftJSON('{"x":01}'), SyntaxError);
  assert.throws(() => parseSwiftJSON('{"x":"unterminated}'), SyntaxError);
  assert.throws(
    () => decodePersistedWorkspace(Uint8Array.from([0xff, 0xfe, 0xfd])),
    /encoded data was not valid|encoding/i,
  );
});

test("workspace persistence rotates three generations and verifies primary", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-workspace-"));
  try {
    const store = new WorkspacePersistence(directory);
    for (let revision = 1; revision <= 4; revision += 1) {
      await store.save(workspace(revision));
    }
    const primary = decodePersistedWorkspace(await readFile(store.primaryPath));
    const backup1 = decodePersistedWorkspace(await readFile(store.backupPath(1)));
    const backup2 = decodePersistedWorkspace(await readFile(store.backupPath(2)));
    const backup3 = decodePersistedWorkspace(await readFile(store.backupPath(3)));
    assert.equal(primary.futureRevision, 4);
    assert.equal(backup1.futureRevision, 3);
    assert.equal(backup2.futureRevision, 2);
    assert.equal(backup3.futureRevision, 1);
    assert.equal((await store.load()).source, "primary");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("workspace persistence CAS preserves external and multi-instance winners", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-workspace-cas-"));
  try {
    const seed = new WorkspacePersistence(directory);
    await seed.save(workspace(1));
    const first = new WorkspacePersistence(directory);
    const second = new WorkspacePersistence(directory);
    await Promise.all([first.load(), second.load()]);

    await first.save({ ...workspace(2), futureExternalEdit: "FIRST_WINS" });
    await assert.rejects(second.save(workspace(3)), /write-conflict/);
    let live = decodePersistedWorkspace(await readFile(first.primaryPath));
    assert.equal(live.futureRevision, 2);
    assert.equal(live.futureExternalEdit, "FIRST_WINS");

    await second.load();
    const external = {
      ...live,
      futureExternalEdit: "EXTERNAL_WINS",
    } as PersistedWorkspaceRecord;
    await writeFile(
      first.primaryPath,
      encodePersistedWorkspace(external, { trailingNewline: true }),
      "utf8",
    );
    await assert.rejects(second.save(workspace(4)), /write-conflict/);
    live = decodePersistedWorkspace(await readFile(first.primaryPath));
    assert.equal(live.futureExternalEdit, "EXTERNAL_WINS");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("workspace load restores an interrupted CAS baseline", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-workspace-cas-recovery-"));
  try {
    const store = new WorkspacePersistence(directory);
    await store.save(workspace(1));
    const baseline = await readFile(store.primaryPath);
    const next = Buffer.from(encodePersistedWorkspace(workspace(2)), "utf8");
    const transactionDirectory = path.join(
      directory,
      `.workspace.json.weibei-transaction-${randomUUID()}`,
    );
    await mkdir(transactionDirectory);
    await Promise.all([
      writeFile(path.join(transactionDirectory, "next"), next),
      writeFile(
        path.join(transactionDirectory, "transaction.json"),
        JSON.stringify({
          schemaVersion: 1,
          targetFileName: "workspace.json",
          expectedDigest: sha256(baseline),
          nextDigest: sha256(next),
        }),
        "utf8",
      ),
    ]);
    await rename(store.primaryPath, path.join(transactionDirectory, "previous"));

    const recovered = await new WorkspacePersistence(directory).load();
    assert.equal(recovered.source, "primary");
    assert.equal(recovered.snapshot?.futureRevision, 1);
    assert.deepEqual(await readFile(store.primaryPath), baseline);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("identity-bound workspace save rejects a parent swap after preflight", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-workspace-parent-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "weibei-workspace-outside-"));
  const held = `${directory}-held-${randomUUID()}`;
  try {
    await new WorkspacePersistence(directory).save(workspace(1));
    const info = await lstat(directory, { bigint: true });
    const store = new WorkspacePersistence({
      workspaceDirectory: directory,
      expectedParent: {
        absolutePath: await realpath(directory),
        dev: info.dev,
        ino: info.ino,
      },
    });
    await store.load();
    const outsidePath = path.join(outside, "workspace.json");
    const outsideBytes = Buffer.from(encodePersistedWorkspace({
      ...workspace(99),
      futureExternalEdit: "OUTSIDE_WINNER",
    }, { trailingNewline: true }));
    await writeFile(outsidePath, outsideBytes);
    const originalPrepare = Reflect.get(
      store,
      "prepareParent",
    ) as () => Promise<void>;
    Reflect.set(store, "prepareParent", async () => {
      await originalPrepare.call(store);
      await rename(directory, held);
      await symlink(
        outside,
        directory,
        process.platform === "win32" ? "junction" : "dir",
      );
    });

    await assert.rejects(store.save(workspace(2)), /directory-identity-conflict/);
    assert.deepEqual(await readFile(outsidePath), outsideBytes);
    assert.deepEqual(await readdir(outside), ["workspace.json"]);
  } finally {
    await rm(directory, { recursive: true, force: true });
    await rm(held, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("corrupt primary is quarantined and newest valid backup is selected", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-recovery-"));
  try {
    const fixedNow = new Date("2026-08-29T08:00:01.234Z");
    const store = new WorkspacePersistence({
      workspaceDirectory: directory,
      now: () => fixedNow,
    });
    await store.save(workspace(1));
    await store.save(workspace(2));
    await writeFile(store.primaryPath, "{ definitely corrupt", "utf8");

    const recovered = await store.load();
    assert.equal(recovered.source, "backup-1");
    assert.equal(recovered.notice, "restored-from-backup");
    assert.equal(recovered.needsPrimaryRewrite, true);
    assert.equal(recovered.snapshot?.futureRevision, 1);
    assert.match(
      path.basename(recovered.quarantinedPath ?? ""),
      /^workspace\.corrupt-20260829-080001-234\.json$/,
    );
    assert.equal(await readFile(recovered.quarantinedPath!, "utf8"), "{ definitely corrupt");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("recovery skips a corrupt newer backup and keeps only three corrupt files", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-recovery-chain-"));
  try {
    let clock = 0;
    const store = new WorkspacePersistence({
      workspaceDirectory: directory,
      now: () => new Date(Date.UTC(2026, 7, 29, 9, 0, clock++)),
    });
    await store.save(workspace(1));
    await store.save(workspace(2));
    await store.save(workspace(3));
    await writeFile(store.primaryPath, "bad-primary", "utf8");
    await writeFile(store.backupPath(1), "bad-backup", "utf8");
    const recovered = await store.load();
    assert.equal(recovered.source, "backup-2");
    assert.equal(recovered.snapshot?.futureRevision, 1);

    for (let index = 0; index < 4; index += 1) {
      await writeFile(store.primaryPath, `bad-${index}`, "utf8");
      await store.load();
    }
    const corrupt = (await readdir(directory)).filter((name) =>
      name.startsWith("workspace.corrupt-"),
    );
    assert.equal(corrupt.length, 3);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

function workspace(revision: number): PersistedWorkspaceRecord {
  return {
    importedItems: [],
    notesByItemID: {},
    futureRevision: revision,
    coursePortableStateRevisions: {
      "00000000-0000-0000-0000-000000000001":
        18_446_744_073_709_551_615n - BigInt(revision),
    },
    interfaceTextScaleRaw: "future-scale",
  };
}
