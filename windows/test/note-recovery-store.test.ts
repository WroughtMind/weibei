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
  NoteRecoveryStore,
  noteRecoveryFileName,
} from "../src/main/services/note-recovery-store";

const digest = "a".repeat(64);

test("recovery text round-trips from userData and clear removes it", async () => {
  await withFixture(async ({ store, userDataPath }) => {
    const saved = await store.save({
      itemId: "课程/notes:一",
      markdown: "# 尚未写盘\n",
      baselineDigest: digest.toUpperCase(),
    });
    assert.deepEqual(await store.load(saved.itemId), {
      ...saved,
      baselineDigest: digest,
    });
    assert.match(noteRecoveryFileName(saved.itemId), /^[a-f0-9]{64}\.json$/);
    assert.deepEqual(await readdir(path.join(userDataPath, "note-recovery")), [
      noteRecoveryFileName(saved.itemId),
    ]);

    await store.clear(saved.itemId);
    assert.equal(await store.load(saved.itemId), null);
    await store.clear(saved.itemId);
  });
});

test("concurrent saves are committed in call order so the last edit wins", async () => {
  await withFixture(async ({ store }) => {
    await Promise.all([
      store.save({ itemId: "note-1", markdown: "first", baselineDigest: null }),
      store.save({ itemId: "note-1", markdown: "last", baselineDigest: digest }),
    ]);
    const loaded = await store.load("note-1");
    assert.equal(loaded?.markdown, "last");
    assert.equal(loaded?.baselineDigest, digest);
  });
});

test("bad JSON and an orphaned atomic stage are isolated", async () => {
  await withFixture(async ({ store, userDataPath }) => {
    const recoveryRoot = path.join(userDataPath, "note-recovery");
    await mkdir(recoveryRoot, { recursive: true });
    const fileName = noteRecoveryFileName("note-1");
    await writeFile(path.join(recoveryRoot, fileName), "{broken", "utf8");
    await writeFile(path.join(recoveryRoot, `.${fileName}.stage-crash`), "newer", "utf8");

    assert.equal(await store.load("note-1"), null);
    const saved = await store.save({
      itemId: "note-1",
      markdown: "recovered after restart",
      baselineDigest: null,
    });
    assert.equal((await store.load("note-1"))?.markdown, saved.markdown);
    assert.equal(
      await readFile(path.join(recoveryRoot, `.${fileName}.stage-crash`), "utf8"),
      "newer",
    );
  });
});

test("symbolic recovery files are never followed", async (t) => {
  await withFixture(async ({ store, userDataPath, directory }) => {
    const recoveryRoot = path.join(userDataPath, "note-recovery");
    await mkdir(recoveryRoot, { recursive: true });
    const referent = path.join(directory, "outside.json");
    const original = "outside must remain unchanged";
    await writeFile(referent, original, "utf8");
    try {
      await symlink(referent, path.join(recoveryRoot, noteRecoveryFileName("note-1")));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "EPERM") {
        t.skip("symbolic links are not enabled on this Windows host");
        return;
      }
      throw error;
    }

    assert.equal(await store.load("note-1"), null);
    await assert.rejects(
      store.save({ itemId: "note-1", markdown: "unsafe", baselineDigest: null }),
      /unsafe-note-recovery-target/,
    );
    assert.equal(await readFile(referent, "utf8"), original);
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
