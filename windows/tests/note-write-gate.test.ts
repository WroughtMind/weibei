import assert from "node:assert/strict";
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  NoteWriteGate,
  noteContentDigest,
  sanitizeNoteBackupItemId,
} from "../src/main/services/note-write-gate";

test("new notes require a null baseline and are atomically verified", async () => {
  await withFixture(async ({ gate, notePath }) => {
    const result = await gate.write({
      itemId: "note-1",
      filePath: notePath,
      markdown: "# 第一稿\n",
      baselineDigest: null,
    });
    assert.deepEqual(result, {
      status: "saved",
      digest: noteContentDigest("# 第一稿\n"),
      diskMarkdown: "# 第一稿\n",
      backupPath: null,
    });
    assert.equal(await readFile(notePath, "utf8"), "# 第一稿\n");
    assert.deepEqual(
      (await readdir(path.dirname(notePath))).filter((name) =>
        name.includes("weibei-stage"),
      ),
      [],
    );
  });
});

test("existing notes refuse a missing baseline without touching disk", async () => {
  await withFixture(async ({ gate, notePath }) => {
    await writeFile(notePath, "external truth", "utf8");
    const result = await gate.write({
      itemId: "note-1",
      filePath: notePath,
      markdown: "unsafe overwrite",
      baselineDigest: null,
    });
    assert.equal(result.status, "unavailable");
    assert.equal(result.reason, "baseline-required");
    assert.equal(result.digest, noteContentDigest("external truth"));
    assert.equal(result.diskMarkdown, "external truth");
    assert.equal(await readFile(notePath, "utf8"), "external truth");
    assert.equal((await gate.listBackups("note-1")).length, 0);
  });
});

test("stale baseline produces a conflict and retains the proposed content outside disk", async () => {
  await withFixture(async ({ gate, notePath }) => {
    await writeFile(notePath, "externally changed", "utf8");
    const result = await gate.write({
      itemId: "note-1",
      filePath: notePath,
      markdown: "draft that the caller must retain",
      baselineDigest: noteContentDigest("older baseline"),
    });
    assert.equal(result.status, "conflict");
    assert.equal(result.reason, "baseline-mismatch");
    assert.equal(result.diskMarkdown, "externally changed");
    assert.equal(result.digest, noteContentDigest("externally changed"));
    assert.equal(await readFile(notePath, "utf8"), "externally changed");
  });
});

test("successful overwrite captures exact old bytes in a Windows-safe backup", async () => {
  await withFixture(async ({ gate, notePath }) => {
    const oldMarkdown = "old\r\nbytes\r\n";
    const newMarkdown = "new\nbytes\n";
    await writeFile(notePath, oldMarkdown, "utf8");
    const result = await gate.write({
      itemId: "course/note:1",
      filePath: notePath,
      markdown: newMarkdown,
      baselineDigest: noteContentDigest(oldMarkdown),
    });
    assert.equal(result.status, "saved");
    assert.equal(result.digest, noteContentDigest(newMarkdown));
    assert.ok(result.backupPath);
    assert.equal(await readFile(notePath, "utf8"), newMarkdown);
    assert.equal(await readFile(result.backupPath!, "utf8"), oldMarkdown);
    assert.doesNotMatch(path.basename(result.backupPath!), /:/);
    assert.equal(path.basename(path.dirname(result.backupPath!)), "course_note_1");
  });
});

test("backup failure is a hard hold and never permits the overwrite", async () => {
  await withFixture(async ({ gate, notePath, backupRootPath }) => {
    await writeFile(notePath, "protected disk text", "utf8");
    await writeFile(backupRootPath, "not a directory", "utf8");
    const result = await gate.write({
      itemId: "note-1",
      filePath: notePath,
      markdown: "must remain a draft",
      baselineDigest: noteContentDigest("protected disk text"),
    });
    assert.equal(result.status, "unavailable");
    assert.equal(result.reason, "write-failed");
    assert.equal(await readFile(notePath, "utf8"), "protected disk text");
  });
});

test("per-note mutex makes concurrent same-baseline saves resolve as saved plus conflict", async () => {
  await withFixture(async ({ gate, notePath }) => {
    await writeFile(notePath, "base", "utf8");
    const baselineDigest = noteContentDigest("base");
    const results = await Promise.all([
      gate.write({
        itemId: "note-1",
        filePath: notePath,
        markdown: "first",
        baselineDigest,
      }),
      gate.write({
        itemId: "note-1",
        filePath: notePath,
        markdown: "second",
        baselineDigest,
      }),
    ]);
    assert.deepEqual(
      results.map((result) => result.status).sort(),
      ["conflict", "saved"],
    );
    const winning = results.find((result) => result.status === "saved");
    const conflict = results.find((result) => result.status === "conflict");
    assert.ok(winning);
    assert.ok(conflict);
    assert.ok(winning.diskMarkdown === "first" || winning.diskMarkdown === "second");
    assert.equal(conflict.diskMarkdown, winning.diskMarkdown);
    assert.equal(await readFile(notePath, "utf8"), winning.diskMarkdown);
  });
});

test("the process-wide mutex also serializes distinct gate instances", async () => {
  await withFixture(async ({ gate, notePath, backupRootPath }) => {
    const otherGate = new NoteWriteGate({ backupRootPath });
    await writeFile(notePath, "base", "utf8");
    const baselineDigest = noteContentDigest("base");
    const results = await Promise.all([
      gate.write({
        itemId: "note-1",
        filePath: notePath,
        markdown: "one",
        baselineDigest,
      }),
      otherGate.write({
        itemId: "note-1",
        filePath: notePath,
        markdown: "two",
        baselineDigest,
      }),
    ]);
    assert.deepEqual(
      results.map((result) => result.status).sort(),
      ["conflict", "saved"],
    );
    const winning = results.find((result) => result.status === "saved");
    const conflict = results.find((result) => result.status === "conflict");
    assert.ok(winning);
    assert.ok(conflict);
    assert.ok(winning.diskMarkdown === "one" || winning.diskMarkdown === "two");
    assert.equal(conflict.diskMarkdown, winning.diskMarkdown);
    assert.equal(await readFile(notePath, "utf8"), winning.diskMarkdown);
  });
});

test("a removed file conflicts when the caller supplied an observed baseline", async () => {
  await withFixture(async ({ gate, notePath }) => {
    const result = await gate.write({
      itemId: "note-1",
      filePath: notePath,
      markdown: "do not recreate over an external deletion",
      baselineDigest: noteContentDigest("previous"),
    });
    assert.equal(result.status, "conflict");
    assert.equal(result.reason, "file-removed");
    await assert.rejects(readFile(notePath), /ENOENT/);
  });
});

test("symbolic-link note targets are rejected and their referent is unchanged", async (t) => {
  if (process.platform === "win32") {
    t.skip("creating symlinks may require Windows Developer Mode");
    return;
  }
  await withFixture(async ({ gate, notePath, directory }) => {
    const referent = path.join(directory, "referent.md");
    await writeFile(referent, "referent", "utf8");
    await symlink(referent, notePath);
    const result = await gate.write({
      itemId: "note-1",
      filePath: notePath,
      markdown: "must not follow",
      baselineDigest: noteContentDigest("referent"),
    });
    assert.equal(result.status, "unavailable");
    assert.equal(result.reason, "unsafe-target");
    assert.equal(await readFile(referent, "utf8"), "referent");
  });
});

test("backup ring enforces per-item and global caps", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-note-ring-"));
  const notes = path.join(directory, "notes");
  const backups = path.join(directory, "backups");
  await mkdir(notes);
  try {
    let tick = 0;
    const gate = new NoteWriteGate({
      backupRootPath: backups,
      maxBackupsPerItem: 3,
      maxTotalBackupBytes: 12,
      now: () => new Date(1_700_000_000_000 + tick++ * 1_000),
    });
    const notePath = path.join(notes, "ring.md");
    await writeFile(notePath, "0000", "utf8");
    let baseline = noteContentDigest("0000");
    for (const markdown of ["1111", "2222", "3333", "4444", "5555"]) {
      const result = await gate.write({
        itemId: "ring",
        filePath: notePath,
        markdown,
        baselineDigest: baseline,
      });
      assert.equal(result.status, "saved");
      baseline = result.digest!;
    }
    const entries = await gate.listBackups("ring");
    assert.ok(entries.length <= 3);
    assert.ok(entries.reduce((sum, entry) => sum + entry.byteCount, 0) <= 12);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("backup item IDs are deterministic and bounded", () => {
  assert.equal(sanitizeNoteBackupItemId("../course/note:1"), "course_note_1");
  assert.equal(sanitizeNoteBackupItemId("课程一/笔记"), "课程一_笔记");
  assert.equal(sanitizeNoteBackupItemId("..."), "item");
  assert.equal(sanitizeNoteBackupItemId("x".repeat(200)).length, 120);
});

interface Fixture {
  directory: string;
  backupRootPath: string;
  notePath: string;
  gate: NoteWriteGate;
}

async function withFixture(operation: (fixture: Fixture) => Promise<void>): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-note-gate-"));
  const noteDirectory = path.join(directory, "notes");
  const backupRootPath = path.join(directory, "backups");
  await mkdir(noteDirectory);
  const fixture: Fixture = {
    directory,
    backupRootPath,
    notePath: path.join(noteDirectory, "note.md"),
    gate: new NoteWriteGate({
      backupRootPath,
      now: () => new Date("2026-08-29T08:01:02.345Z"),
    }),
  };
  try {
    await operation(fixture);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}
