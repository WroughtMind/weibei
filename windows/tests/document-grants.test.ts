import assert from "node:assert/strict";
import {
  mkdir,
  mkdtemp,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  DocumentGrantError,
  DocumentGrantService,
  parseDocumentGrantURL,
} from "../src/main/services/document-grants.ts";

test("document grants are opaque, scoped, expiring, and revocable", async (t) => {
  const directory = await temporaryDirectory(t);
  const filePath = path.join(directory, "lesson.pdf");
  await writeFile(filePath, "course material");
  let now = 1_000;
  const grants = new DocumentGrantService({ now: () => now, defaultTTLMS: 100 });

  const first = await grants.issue({
    rootPath: directory,
    filePath,
    scope: "reader-window-1",
  });
  const second = await grants.issue({
    rootPath: directory,
    filePath,
    scope: "reader-window-1",
  });
  assert.notEqual(first.url, second.url);
  assert.equal(first.url.includes(filePath), false);
  assert.equal(first.url.includes("lesson.pdf"), false);
  assert.deepEqual(Object.keys(first).sort(), ["expiresAtMS", "url"]);
  assert.match(first.url, /^weibei-document:\/\/grant\/[A-Za-z0-9_-]{43}$/u);

  const response = await grants.handleRequest(new Request(first.url), "reader-window-1");
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "course material");
  assert.equal(
    (await grants.handleRequest(new Request(second.url), "reader-window-2")).status,
    404,
  );

  assert.equal(grants.revoke(second.url, "reader-window-2"), false);
  assert.equal(grants.revoke(second.url, "reader-window-1"), true);
  assert.equal(
    (await grants.handleRequest(new Request(second.url), "reader-window-1")).status,
    404,
  );

  const expiring = await grants.issue({
    rootPath: directory,
    filePath,
    scope: "reader-window-1",
  });
  now = expiring.expiresAtMS;
  assert.equal(
    (await grants.handleRequest(new Request(expiring.url), "reader-window-1")).status,
    404,
  );

  const scopedA = await grants.issue({ rootPath: directory, filePath, scope: "scope-a" });
  const scopedB = await grants.issue({ rootPath: directory, filePath, scope: "scope-a" });
  assert.equal(grants.revokeScope("scope-a"), 2);
  assert.equal((await grants.handleRequest(new Request(scopedA.url), "scope-a")).status, 404);
  assert.equal((await grants.handleRequest(new Request(scopedB.url), "scope-a")).status, 404);
});

test("document grant URL parser rejects authority and path smuggling", () => {
  const token = "a".repeat(43);
  const valid = `weibei-document://grant/${token}`;
  assert.equal(parseDocumentGrantURL(valid), token);

  for (const value of [
    `https://grant/${token}`,
    `weibei-document://other/${token}`,
    `weibei-document://user@grant/${token}`,
    `weibei-document://grant:42/${token}`,
    `weibei-document://grant/${token}/extra`,
    `weibei-document://grant/${token}?download=1`,
    `weibei-document://grant/${token}#fragment`,
    `weibei-document://grant/${"a".repeat(42)}`,
    `weibei-document://grant/%61${"a".repeat(42)}`,
  ]) {
    assert.equal(parseDocumentGrantURL(value), null, value);
  }
});

test("document grants enforce realpath containment and regular files", async (t) => {
  const parent = await temporaryDirectory(t);
  const root = path.join(parent, "root");
  const outside = path.join(parent, "outside.txt");
  await mkdir(root);
  await writeFile(outside, "outside");
  const grants = new DocumentGrantService();

  await assert.rejects(
    grants.issue({ rootPath: root, filePath: outside, scope: "reader" }),
    isGrantError("outside-root"),
  );
  await assert.rejects(
    grants.issue({ rootPath: root, filePath: root, scope: "reader" }),
    isGrantError("not-a-regular-file"),
  );

  const linked = path.join(root, "linked.txt");
  try {
    await symlink(outside, linked, "file");
  } catch (error) {
    if (isErrno(error, "EPERM") || isErrno(error, "EACCES")) {
      t.skip("The Windows runner does not permit creating test symlinks.");
      return;
    }
    throw error;
  }
  await assert.rejects(
    grants.issue({ rootPath: root, filePath: linked, scope: "reader" }),
    isGrantError("outside-root"),
  );
});

test("document grants revalidate the path before every stream", async (t) => {
  const parent = await temporaryDirectory(t);
  const root = path.join(parent, "root");
  const target = path.join(root, "target.txt");
  const outside = path.join(parent, "outside.txt");
  await mkdir(root);
  await writeFile(target, "inside");
  await writeFile(outside, "outside");
  const grants = new DocumentGrantService();
  const grant = await grants.issue({ rootPath: root, filePath: target, scope: "reader" });

  await rm(target);
  try {
    await symlink(outside, target, "file");
  } catch (error) {
    if (isErrno(error, "EPERM") || isErrno(error, "EACCES")) {
      t.skip("The Windows runner does not permit creating test symlinks.");
      return;
    }
    throw error;
  }
  const response = await grants.handleRequest(new Request(grant.url), "reader");
  assert.equal(response.status, 404);
});

test("document protocol streams complete and ranged responses", async (t) => {
  const directory = await temporaryDirectory(t);
  const filePath = path.join(directory, "digits.pdf");
  const emptyPath = path.join(directory, "empty.pdf");
  await writeFile(filePath, "0123456789");
  await writeFile(emptyPath, "");
  const grants = new DocumentGrantService();
  const grant = await grants.issue({ rootPath: directory, filePath, scope: "reader" });

  const complete = await grants.handleRequest(new Request(grant.url), "reader");
  assert.equal(complete.status, 200);
  assert.equal(complete.headers.get("content-length"), "10");
  assert.equal(complete.headers.get("accept-ranges"), "bytes");
  assert.equal(complete.headers.get("access-control-allow-origin"), "*");
  assert.match(
    complete.headers.get("access-control-expose-headers") ?? "",
    /Content-Range/u,
  );
  assert.equal(complete.headers.get("content-type"), "application/pdf");
  assert.equal(await complete.text(), "0123456789");

  await expectRange(grants, grant.url, "bytes=2-5", 206, "2345", "bytes 2-5/10");
  await expectRange(grants, grant.url, "bytes=7-", 206, "789", "bytes 7-9/10");
  await expectRange(grants, grant.url, "bytes=-3", 206, "789", "bytes 7-9/10");
  await expectRange(grants, grant.url, "bytes=0-999", 206, "0123456789", "bytes 0-9/10");

  for (const range of ["bytes=20-30", "bytes=5-2", "bytes=-0", "bytes=0-1,4-5", "items=0-1"]) {
    const response = await grants.handleRequest(
      new Request(grant.url, { headers: { Range: range } }),
      "reader",
    );
    assert.equal(response.status, 416, range);
    assert.equal(response.headers.get("content-range"), "bytes */10");
    assert.equal(await response.text(), "");
  }

  const head = await grants.handleRequest(
    new Request(grant.url, { method: "HEAD", headers: { Range: "bytes=0-0" } }),
    "reader",
  );
  assert.equal(head.status, 206);
  assert.equal(head.headers.get("content-length"), "1");
  assert.equal(head.headers.get("content-range"), "bytes 0-0/10");
  assert.equal(await head.text(), "");

  const post = await grants.handleRequest(
    new Request(grant.url, { method: "POST" }),
    "reader",
  );
  assert.equal(post.status, 405);
  assert.equal(post.headers.get("allow"), "GET, HEAD");

  const emptyGrant = await grants.issue({
    rootPath: directory,
    filePath: emptyPath,
    scope: "reader",
  });
  const empty = await grants.handleRequest(new Request(emptyGrant.url), "reader");
  assert.equal(empty.status, 200);
  assert.equal(empty.headers.get("content-length"), "0");
  assert.equal(await empty.text(), "");
  const emptyRange = await grants.handleRequest(
    new Request(emptyGrant.url, { headers: { Range: "bytes=0-0" } }),
    "reader",
  );
  assert.equal(emptyRange.status, 416);
  assert.equal(emptyRange.headers.get("content-range"), "bytes */0");
});

test("document protocol exposes a stream rather than an IPC-sized byte payload", async (t) => {
  const directory = await temporaryDirectory(t);
  const filePath = path.join(directory, "large.pdf");
  const size = 2 * 1024 * 1024;
  await writeFile(filePath, Buffer.alloc(size, 0x61));
  const grants = new DocumentGrantService();
  const grant = await grants.issue({ rootPath: directory, filePath, scope: "reader" });

  assert.deepEqual(Object.keys(grant).sort(), ["expiresAtMS", "url"]);
  const response = await grants.handleRequest(new Request(grant.url), "reader");
  assert.equal(response.headers.get("content-length"), String(size));
  assert.ok(response.body instanceof ReadableStream);
  const reader = response.body.getReader();
  const firstChunk = await reader.read();
  assert.equal(firstChunk.done, false);
  assert.ok(firstChunk.value.byteLength > 0);
  assert.ok(firstChunk.value.byteLength < size);
  await reader.cancel();
});

async function expectRange(
  grants: DocumentGrantService,
  url: string,
  range: string,
  status: number,
  body: string,
  contentRange: string,
): Promise<void> {
  const response = await grants.handleRequest(
    new Request(url, { headers: { Range: range } }),
    "reader",
  );
  assert.equal(response.status, status);
  assert.equal(response.headers.get("content-range"), contentRange);
  assert.equal(await response.text(), body);
}

function isGrantError(code: DocumentGrantError["code"]): (error: unknown) => boolean {
  return (error) => error instanceof DocumentGrantError && error.code === code;
}

function isErrno(error: unknown, code: string): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as NodeJS.ErrnoException).code === code
  );
}

async function temporaryDirectory(t: { after(callback: () => unknown): void }): Promise<string> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-grant-test-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}
