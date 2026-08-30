import assert from "node:assert/strict";
import { createHash } from "node:crypto";
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
  NoteRecoveryStore,
  noteRecoveryFileName,
} from "../src/main/services/note-recovery-store";

const digest = "a".repeat(64);
const courseA = "11111111-1111-4111-8111-111111111111";
const courseB = "22222222-2222-4222-8222-222222222222";

test("recovery text round-trips from userData and clear removes it", async () => {
  await withFixture(async ({ store, userDataPath, directory }) => {
    const target = scope(directory, courseA, "课程/notes:一");
    const saved = await store.save({
      ...target,
      markdown: "# 尚未写盘\n",
      baselineDigest: digest.toUpperCase(),
    });
    assert.deepEqual(await store.load(target), {
      ...saved,
      baselineDigest: digest,
    });
    assert.match(noteRecoveryFileName(target), /^[a-f0-9]{64}\.json$/);
    assert.deepEqual(await readdir(path.join(userDataPath, "note-recovery")), [
      noteRecoveryFileName(target),
    ]);

    await store.clear(target);
    assert.equal(await store.load(target), null);
    await store.clear(target);
  });
});

test("concurrent saves are committed in call order so the last edit wins", async () => {
  await withFixture(async ({ store, directory }) => {
    const target = scope(directory, courseA, "note-1");
    await Promise.all([
      store.save({ ...target, markdown: "first", baselineDigest: null }),
      store.save({ ...target, markdown: "last", baselineDigest: digest }),
    ]);
    const loaded = await store.load(target);
    assert.equal(loaded?.markdown, "last");
    assert.equal(loaded?.baselineDigest, digest);
  });
});

test("bad JSON and an orphaned atomic stage are isolated", async () => {
  await withFixture(async ({ store, userDataPath, directory }) => {
    const target = scope(directory, courseA, "note-1");
    const recoveryRoot = path.join(userDataPath, "note-recovery");
    await mkdir(recoveryRoot, { recursive: true });
    const fileName = noteRecoveryFileName(target);
    await writeFile(path.join(recoveryRoot, fileName), "{broken", "utf8");
    await writeFile(path.join(recoveryRoot, `.${fileName}.stage-crash`), "newer", "utf8");

    assert.equal(await store.load(target), null);
    const saved = await store.save({
      ...target,
      markdown: "recovered after restart",
      baselineDigest: null,
    });
    assert.equal((await store.load(target))?.markdown, saved.markdown);
    assert.equal(
      await readFile(path.join(recoveryRoot, `.${fileName}.stage-crash`), "utf8"),
      "newer",
    );
  });
});

test("symbolic recovery files are never followed", async (t) => {
  await withFixture(async ({ store, userDataPath, directory }) => {
    const target = scope(directory, courseA, "note-1");
    const recoveryRoot = path.join(userDataPath, "note-recovery");
    await mkdir(recoveryRoot, { recursive: true });
    const referent = path.join(directory, "outside.json");
    const original = "outside must remain unchanged";
    await writeFile(referent, original, "utf8");
    try {
      await symlink(referent, path.join(recoveryRoot, noteRecoveryFileName(target)));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "EPERM") {
        t.skip("symbolic links are not enabled on this Windows host");
        return;
      }
      throw error;
    }

    assert.equal(await store.load(target), null);
    await assert.rejects(
      store.save({ ...target, markdown: "unsafe", baselineDigest: null }),
      /unsafe-note-recovery-target/,
    );
    assert.equal(await readFile(referent, "utf8"), original);
  });
});

test("same IDs in another library or course never share or clear recovery", async () => {
  await withFixture(async ({ store, directory }) => {
    const rootA = path.join(directory, "library-a");
    const rootB = path.join(directory, "library-b");
    const targetA = scope(rootA, courseA, "same-note");
    const clonedLibraryTarget = scope(rootB, courseA, "same-note");
    const otherCourseTarget = scope(rootA, courseB, "same-note");

    await store.save({ ...targetA, markdown: "A draft", baselineDigest: digest });
    assert.equal(await store.load(clonedLibraryTarget), null);
    assert.equal(await store.load(otherCourseTarget), null);
    assert.notEqual(noteRecoveryFileName(targetA), noteRecoveryFileName(clonedLibraryTarget));
    assert.notEqual(noteRecoveryFileName(targetA), noteRecoveryFileName(otherCourseTarget));

    await store.save({ ...clonedLibraryTarget, markdown: "B draft", baselineDigest: null });
    await store.save({ ...otherCourseTarget, markdown: "course B draft", baselineDigest: null });
    await store.clear(targetA);
    assert.equal((await store.load(clonedLibraryTarget))?.markdown, "B draft");
    assert.equal((await store.load(otherCourseTarget))?.markdown, "course B draft");
  });
});

test("legacy item-only recovery is neither loaded nor deleted automatically", async () => {
  await withFixture(async ({ store, userDataPath, directory }) => {
    const target = scope(directory, courseA, "note-1");
    const recoveryRoot = path.join(userDataPath, "note-recovery");
    await mkdir(recoveryRoot, { recursive: true });
    const legacyFileName = `${createHash("sha256").update(target.itemId, "utf8").digest("hex")}.json`;
    const legacyPath = path.join(recoveryRoot, legacyFileName);
    await writeFile(legacyPath, JSON.stringify({
      schemaVersion: 1,
      itemId: target.itemId,
      markdown: "unscoped draft",
      baselineDigest: null,
      savedAt: "2026-08-29T09:10:11.123Z",
    }), "utf8");

    assert.equal(await store.load(target), null);
    await store.clear(target);
    assert.match(await readFile(legacyPath, "utf8"), /unscoped draft/u);
  });
});

interface Fixture {
  directory: string;
  userDataPath: string;
  store: NoteRecoveryStore;
}

async function withFixture(operation: (fixture: Fixture) => Promise<void>): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-note-recovery-"));
  const userDataPath = path.join(directory, "user-data");
  const store = new NoteRecoveryStore({
    userDataPath,
    now: () => new Date("2026-08-29T09:10:11.123Z"),
  });
  try {
    await operation({ directory, userDataPath, store });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function scope(libraryRootPath: string, courseId: string, itemId: string) {
  return { libraryRootPath, courseId, itemId };
}
