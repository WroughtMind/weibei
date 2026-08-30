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
  watch,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  COURSE_MANIFEST_RELATIVE_PATH,
  COURSE_MATERIALS_DIRECTORY,
  COURSE_NOTES_DIRECTORY,
  COURSE_STATE_RELATIVE_PATH,
  CourseLibrary,
  CourseLibraryError,
} from "../src/main/services/course-library";
import {
  atomicCreateVerified,
  atomicReplaceVerified,
  copyFileExclusiveVerified,
  createDirectoryExclusiveVerified,
  sha256,
} from "../src/main/services/file-utils";
import { StudySessionStore } from "../src/main/services/session-store";
import {
  dateFromSwiftReferenceSeconds,
  parseSwiftJSON,
  stringifySwiftJSON,
  swiftReferenceSecondsFromDate,
  type SwiftJSONObject,
} from "../src/main/services/swift-codec";

test("createCourse writes a Swift-decodable v1 manifest and portable v2 state", async () => {
  await withLibrary(async ({ library }) => {
    const summary = await library.createCourse("碑学入门", 3);
    const manifest = await readSwiftObject(
      path.join(summary.rootPath, COURSE_MANIFEST_RELATIVE_PATH),
    );
    const state = await readSwiftObject(
      path.join(summary.rootPath, COURSE_STATE_RELATIVE_PATH),
    );

    assert.equal(manifest.courseID, summary.id);
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(state.courseID, summary.id);
    assert.equal(state.schemaVersion, 2);
    assert.equal(state.revision, 0);
    assertSwiftDate(state.savedAt);
    const metadata = objectValue(state.metadata);
    assert.equal(metadata.title, "碑学入门");
    assert.equal(metadata.colorIndex, 3);
    assertSwiftDate(metadata.createdAt);
    assertSwiftDate(metadata.updatedAt);
    assert.deepEqual(state.items, []);
    assert.deepEqual(state.studySessions, []);
    assert.deepEqual(state.noteSourceLinks, []);
    assert.deepEqual(state.studyLocationsByItemID, {});
    assert.deepEqual(state.pendingNoteDrafts, []);

    // The same lossless codec must be able to read its own sorted-key output.
    assert.deepEqual(
      parseSwiftJSON(stringifySwiftJSON(state, { sortKeys: true })),
      state,
    );
    assert.deepEqual(
      (await library.listCourses()).map((course) => course.id),
      [summary.id],
    );
    assert.deepEqual(
      (await readdir(summary.rootPath)).sort(),
      [".weibei", COURSE_MATERIALS_DIRECTORY, COURSE_NOTES_DIRECTORY].sort(),
    );
  });
});

test("concurrent CourseLibrary instances claim distinct same-titled course roots", async () => {
  await withLibrary(async ({ rootPath }) => {
    const libraries = Array.from(
      { length: 16 },
      () => new CourseLibrary(rootPath),
    );
    const created = await Promise.all(
      libraries.map((library) => library.createCourse("并发同名课程")),
    );

    assert.equal(new Set(created.map((course) => course.id)).size, created.length);
    assert.equal(
      new Set(created.map((course) => path.resolve(course.rootPath))).size,
      created.length,
    );
    const listed = await new CourseLibrary(rootPath).listCourses();
    assert.equal(listed.length, created.length);
    assert.deepEqual(
      new Set(listed.map((course) => course.id)),
      new Set(created.map((course) => course.id)),
    );
  });
});

test("an external directory that wins after name selection is never adopted", async () => {
  await withLibrary(async ({ rootPath, library }) => {
    const selectedPath = path.join(rootPath, "外部抢占课程");

    // Simulate Finder/iCloud creating the selected candidate after the caller
    // scanned names but before its exclusive mkdir. The primitive must surface
    // EEXIST and must not touch any content at the winning path.
    await mkdir(selectedPath);
    const sentinelPath = path.join(selectedPath, "EXTERNAL.txt");
    await writeFile(sentinelPath, "external winner", "utf8");
    await assert.rejects(
      createDirectoryExclusiveVerified(selectedPath, rootPath),
      isNodeErrorCode("EEXIST"),
    );

    const created = await library.createCourse("外部抢占课程");
    assert.notEqual(path.resolve(created.rootPath), path.resolve(selectedPath));
    assert.equal(await readFile(sentinelPath, "utf8"), "external winner");
    assert.deepEqual(await readdir(selectedPath), ["EXTERNAL.txt"]);
  });
});

test("exclusive directory claims have exactly one concurrent winner", async () => {
  await withLibrary(async ({ rootPath }) => {
    const targetPath = path.join(rootPath, "单一赢家");
    const results = await Promise.allSettled([
      createDirectoryExclusiveVerified(targetPath, rootPath),
      createDirectoryExclusiveVerified(targetPath, rootPath),
    ]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    const rejected = results.find((result) => result.status === "rejected");
    assert.ok(rejected && rejected.status === "rejected");
    assert.equal(isNodeErrorCode("EEXIST")(rejected.reason), true);
  });
});

test("Markdown import records a stable byte snapshot and increments portable revision", async () => {
  await withLibrary(async ({ library, directory }) => {
    const course = await library.createCourse("导入课");
    const sourceDirectory = path.join(directory, "incoming");
    await mkdir(sourceDirectory);
    const sourcePath = path.join(sourceDirectory, "拓片.md");
    const sourceBytes = Buffer.from("# 拓片\n\n龙门二十品 e\u0301 👨‍👩‍👧‍👦\n", "utf8");
    await writeFile(sourcePath, sourceBytes);
    const before = await lstat(sourcePath, { bigint: true });

    const [item] = await library.importFiles(course.id, [sourcePath]);
    assert.ok(item);
    assert.equal(item.kind, "markdown");
    assert.equal(item.isNotebookNote, true);
    assert.equal(item.appearsInMaterials, true);
    assert.equal(item.relativePath, `${COURSE_MATERIALS_DIRECTORY}/拓片.md`);
    assert.equal(item.contentDigest, sha256(sourceBytes));
    assert.deepEqual(await readFile(sourcePath), sourceBytes);
    const after = await lstat(sourcePath, { bigint: true });
    assert.equal(after.size, before.size);
    assert.equal(after.mtimeNs, before.mtimeNs);

    const state = await readSwiftObject(
      path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    assert.equal(state.revision, 1);
    assertSwiftDate(state.savedAt);
    const raw = arrayObjects(state.items)[0];
    assert.equal(raw.itemID, item.id);
    assert.equal(raw.courseRelativePath, item.relativePath);
    assert.deepEqual(raw.storage, { kind: "courseOwned" });
    assert.equal(raw.contentRevision, 1);
    assert.equal(raw.contentDigest, sha256(sourceBytes));
    assert.equal(raw.fileByteCount, sourceBytes.byteLength);
    assert.equal(typeof raw.fileModificationTimeNanoseconds, "bigint");
    assertSwiftDate(raw.membershipCreatedAt);

    const opened = await library.openItem(course.id, item.id);
    assert.equal(opened.payload.content, sourceBytes.toString("utf8"));
    assert.equal(opened.payload.digest, sha256(sourceBytes));
    assert.deepEqual(await readFile(opened.absolutePath), sourceBytes);
  });
});

test("case-folded and NFC-equivalent course folder collisions are blocked", async () => {
  await withLibrary(async ({ rootPath }) => {
    await mkdir(path.join(rootPath, "Course"), { recursive: true });
    await mkdir(path.join(rootPath, "course"), { recursive: true });
    const names = await readdir(rootPath);
    if (!names.includes("Course") || !names.includes("course")) return;
    const library = new CourseLibrary(rootPath);
    await assert.rejects(
      library.listCourses(),
      isCourseError("windows-path-collision"),
    );
  });

  await withLibrary(async ({ rootPath }) => {
    const composed = "Café";
    const decomposed = "Cafe\u0301";
    await mkdir(path.join(rootPath, composed), { recursive: true });
    await mkdir(path.join(rootPath, decomposed), { recursive: true });
    const names = await readdir(rootPath);
    if (!names.includes(composed) || !names.includes(decomposed)) return;
    const library = new CourseLibrary(rootPath);
    await assert.rejects(
      library.listCourses(),
      isCourseError("windows-path-collision"),
    );
  });
});

test("duplicate portable course IDs fail closed even when their UUID casing differs", async () => {
  await withLibrary(async ({ rootPath, library }) => {
    const courseID = randomUUID();
    await writeMacCourse(rootPath, {
      folderName: "课程副本 A",
      courseID,
      title: "课程 A",
    });
    await writeMacCourse(rootPath, {
      folderName: "课程副本 B",
      courseID: courseID.toUpperCase(),
      title: "课程 B",
    });

    await assert.rejects(
      library.listCourses(),
      isCourseError("duplicate-course-id"),
    );
    await assert.rejects(
      library.detail(courseID),
      isCourseError("duplicate-course-id"),
    );
  });
});

test("manifest and state UUID casing differences remain the same course", async () => {
  await withLibrary(async ({ rootPath, library }) => {
    const courseID = randomUUID().toUpperCase();
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "UUID Casing",
      courseID,
      title: "UUID 大小写",
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const state = await readSwiftObject(statePath);
    state.courseID = courseID.toLowerCase();
    await writeFile(statePath, stringifySwiftJSON(state, { sortKeys: true }), "utf8");

    assert.deepEqual(
      (await library.listCourses()).map((course) => course.id),
      [courseID],
    );
    assert.equal((await library.detail(courseID.toLowerCase())).id, courseID);
  });
});

test("exclusive placement preserves a destination that wins the naming race", async () => {
  await withLibrary(async ({ directory }) => {
    const target = path.join(directory, "竞态目标.md");
    const source = path.join(directory, "待复制.md");
    await writeFile(source, "import copy", "utf8");

    // The caller selected `target`, then Finder/iCloud created it before the
    // staged file was placed. Neither create path may replace those bytes.
    await writeFile(target, "external winner", "utf8");
    await assert.rejects(
      atomicCreateVerified(target, "new note"),
      isNodeErrorCode("EEXIST"),
    );
    assert.equal(await readFile(target, "utf8"), "external winner");
    await assert.rejects(
      copyFileExclusiveVerified(source, target),
      isNodeErrorCode("EEXIST"),
    );
    assert.equal(await readFile(target, "utf8"), "external winner");
  });
});

test("bound file mutations never follow a parent replaced after staging", async () => {
  await withLibrary(async ({ directory }) => {
    const exerciseSwap = async (
      name: string,
      operation: (fixture: {
        parentPath: string;
        targetPath: string;
        identity: { absolutePath: string; dev: bigint; ino: bigint };
      }) => Promise<unknown>,
    ) => {
      const parentPath = path.join(directory, `${name}-parent`);
      const movedParentPath = path.join(directory, `${name}-parent-moved`);
      const outsidePath = path.join(directory, `${name}-outside`);
      await Promise.all([mkdir(parentPath), mkdir(outsidePath)]);
      const canonicalParent = await realpath(parentPath);
      const parentStats = await lstat(canonicalParent, { bigint: true });
      const identity = {
        absolutePath: canonicalParent,
        dev: parentStats.dev,
        ino: parentStats.ino,
      };
      const targetPath = path.join(parentPath, "state.json");
      const abort = new AbortController();
      const swapped = (async () => {
        try {
          for await (const event of watch(parentPath, { signal: abort.signal })) {
            if (!event.filename?.includes("weibei-")) continue;
            await rename(parentPath, movedParentPath);
            await symlink(
              outsidePath,
              parentPath,
              process.platform === "win32" ? "junction" : "dir",
            );
            return;
          }
        } catch (error) {
          if (!(error instanceof Error) || error.name !== "AbortError") throw error;
        }
      })();
      try {
        await assert.rejects(operation({ parentPath, targetPath, identity }));
        await swapped;
        assert.deepEqual(await readdir(outsidePath), []);
      } finally {
        abort.abort();
        await swapped;
      }
    };

    await exerciseSwap("exclusive-create", async ({ targetPath, identity }) =>
      atomicCreateVerified(targetPath, Buffer.alloc(16 * 1024 * 1024, 0x61), identity));

    await exerciseSwap("conditional-replace", async ({ targetPath, identity }) => {
      const baseline = "external baseline";
      await writeFile(targetPath, baseline, "utf8");
      return atomicReplaceVerified(
        targetPath,
        baseline,
        Buffer.alloc(16 * 1024 * 1024, 0x62),
        identity,
      );
    });
  });
});

test("mac portable states with case or NFC item collisions are not adopted or rewritten", async () => {
  await withLibrary(async ({ rootPath }) => {
    const caseID = randomUUID();
    const nfcID = randomUUID();
    const caseRoot = await writeMacCourse(rootPath, {
      folderName: "Case Collision",
      courseID: caseID,
      title: "大小写冲突",
      items: [
        portableItem("case-a", `${COURSE_MATERIALS_DIRECTORY}/A.md`),
        portableItem("case-b", `${COURSE_MATERIALS_DIRECTORY}/a.md`),
      ],
    });
    const nfcRoot = await writeMacCourse(rootPath, {
      folderName: "NFC Collision",
      courseID: nfcID,
      title: "NFC 冲突",
      items: [
        portableItem("nfc-a", `${COURSE_MATERIALS_DIRECTORY}/Café.md`),
        portableItem("nfc-b", `${COURSE_MATERIALS_DIRECTORY}/Cafe\u0301.md`),
      ],
    });
    const caseStatePath = path.join(caseRoot, COURSE_STATE_RELATIVE_PATH);
    const nfcStatePath = path.join(nfcRoot, COURSE_STATE_RELATIVE_PATH);
    const [caseBefore, nfcBefore] = await Promise.all([
      readFile(caseStatePath),
      readFile(nfcStatePath),
    ]);

    const library = new CourseLibrary(rootPath);
    assert.deepEqual(await library.listCourses(), []);
    await assert.rejects(library.detail(caseID), isCourseError("course-not-found"));
    await assert.rejects(library.detail(nfcID), isCourseError("course-not-found"));
    assert.deepEqual(await readFile(caseStatePath), caseBefore);
    assert.deepEqual(await readFile(nfcStatePath), nfcBefore);
  });
});

test("duplicate exact item paths cannot authorize a discarded v1 Chat item", async () => {
  await withLibrary(async ({ rootPath }) => {
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Duplicate Exact Path",
      courseID,
      title: "重复路径",
      items: [
        portableItem("first-item", `${COURSE_MATERIALS_DIRECTORY}/同一路径.md`),
        portableItem("discarded-item", `${COURSE_MATERIALS_DIRECTORY}/同一路径.md`),
      ],
      extraState: {
        schemaVersion: 1,
        studySessions: [{
          id: randomUUID(),
          title: "不能授权第二项",
          messages: [{
            id: randomUUID(),
            role: "user",
            text: "引用 discarded item",
            sources: [{ itemID: "discarded-item", courseID, kind: "material" }],
            createdAt,
          }],
          relatedCourseIDs: [courseID],
          focusItemIDs: ["discarded-item"],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const before = await readFile(statePath);
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });

    assert.deepEqual(await library.listCourses(), []);
    await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
    assert.equal(migrationCalls, 0);
    assert.deepEqual(await readFile(statePath), before);
  });
});

test("createNote writes canonical Markdown under 笔记 and registers a portable note", async () => {
  await withLibrary(async ({ library }) => {
    const course = await library.createCourse("笔记课");
    const note = await library.createNote(course.id, "石门铭");
    assert.equal(note.kind, "markdown");
    assert.equal(note.isNotebookNote, true);
    assert.equal(note.appearsInMaterials, false);
    assert.equal(note.relativePath, `${COURSE_NOTES_DIRECTORY}/石门铭.md`);

    const notePath = path.join(course.rootPath, COURSE_NOTES_DIRECTORY, "石门铭.md");
    assert.equal(await readFile(notePath, "utf8"), "# 石门铭\n\n");
    const state = await readSwiftObject(
      path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    assert.equal(state.revision, 1);
    const raw = arrayObjects(state.items)[0];
    assert.equal(raw.itemID, note.id);
    assert.equal(raw.courseRelativePath, note.relativePath);
    assert.equal(raw.isNotebookNote, true);
    assert.equal(raw.appearsInMaterials, false);
    assert.deepEqual(raw.storage, { kind: "courseOwned" });
    assert.equal(raw.contentDigest, sha256("# 石门铭\n\n"));
  });
});

test("course writes reject material, note, and metadata directory links", async (t) => {
  await withLibrary(async ({ library, directory }) => {
    const linkDirectory = async (outsidePath: string, coursePath: string) => {
      await rm(coursePath, { recursive: true });
      await symlink(
        outsidePath,
        coursePath,
        process.platform === "win32" ? "junction" : "dir",
      );
    };

    const noteCourse = await library.createCourse("笔记目录链接");
    const outsideNotes = path.join(directory, "outside-notes");
    await mkdir(outsideNotes);
    try {
      await linkDirectory(
        outsideNotes,
        path.join(noteCourse.rootPath, COURSE_NOTES_DIRECTORY),
      );
    } catch (error) {
      if (process.platform === "win32") {
        t.diagnostic(`directory link assertions skipped: ${String(error)}`);
        return;
      }
      throw error;
    }
    const noteStateBefore = await readFile(
      path.join(noteCourse.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    await assert.rejects(library.createNote(noteCourse.id, "OUTSIDE"));
    assert.deepEqual(await readdir(outsideNotes), []);
    assert.deepEqual(
      await readFile(path.join(noteCourse.rootPath, COURSE_STATE_RELATIVE_PATH)),
      noteStateBefore,
    );

    const importCourse = await library.createCourse("资料目录链接");
    const outsideMaterials = path.join(directory, "outside-materials");
    await mkdir(outsideMaterials);
    await linkDirectory(
      outsideMaterials,
      path.join(importCourse.rootPath, COURSE_MATERIALS_DIRECTORY),
    );
    const sourcePath = path.join(directory, "OUTSIDE.md");
    await writeFile(sourcePath, "must stay at source", "utf8");
    const importStateBefore = await readFile(
      path.join(importCourse.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    await assert.rejects(library.importFiles(importCourse.id, [sourcePath]));
    assert.deepEqual(await readdir(outsideMaterials), []);
    assert.deepEqual(
      await readFile(path.join(importCourse.rootPath, COURSE_STATE_RELATIVE_PATH)),
      importStateBefore,
    );

    const metadataCourse = await library.createCourse("元数据目录链接");
    const metadataPath = path.join(metadataCourse.rootPath, ".weibei");
    const outsideMetadata = path.join(directory, "outside-metadata");
    await mkdir(outsideMetadata);
    const manifestBytes = await readFile(
      path.join(metadataCourse.rootPath, COURSE_MANIFEST_RELATIVE_PATH),
    );
    const stateBytes = await readFile(
      path.join(metadataCourse.rootPath, COURSE_STATE_RELATIVE_PATH),
    );
    await writeFile(path.join(outsideMetadata, "course.json"), manifestBytes);
    await writeFile(path.join(outsideMetadata, "course-state.json"), stateBytes);
    await linkDirectory(outsideMetadata, metadataPath);
    const outsideStateBefore = await readFile(
      path.join(outsideMetadata, "course-state.json"),
    );
    await assert.rejects(library.createNote(metadataCourse.id, "OUTSIDE"));
    assert.deepEqual(
      await readFile(path.join(outsideMetadata, "course-state.json")),
      outsideStateBefore,
    );
    assert.equal(
      (await library.listCourses()).some((course) => course.id === metadataCourse.id),
      false,
    );
  });
});

test("unsafe traversal, leaf symlinks, and symlink import sources are rejected", async (t) => {
  await withLibrary(async ({ library, rootPath, directory }) => {
    const traversalID = randomUUID();
    await writeMacCourse(rootPath, {
      folderName: "Traversal",
      courseID: traversalID,
      title: "越界课程",
      items: [portableItem("escape", `${COURSE_MATERIALS_DIRECTORY}/../笔记/escape.md`)],
    });
    assert.equal(
      (await library.listCourses()).some((course) => course.id === traversalID),
      false,
    );

    const course = await library.createCourse("链接课");
    const realPath = path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY, "real.md");
    const linkPath = path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY, "link.md");
    await writeFile(realPath, "real body", "utf8");
    try {
      await symlink("real.md", linkPath);
    } catch (error) {
      if (process.platform === "win32") {
        t.diagnostic(`symlink assertions skipped: ${String(error)}`);
        return;
      }
      throw error;
    }
    const statePath = path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH);
    const state = await readSwiftObject(statePath);
    state.items = [
      {
        ...portableItem("link-item", `${COURSE_MATERIALS_DIRECTORY}/link.md`),
        contentDigest: sha256("real body"),
        fileByteCount: 9,
      },
    ];
    await writeFile(statePath, stringifySwiftJSON(state, { sortKeys: true }), "utf8");
    assert.equal((await library.detail(course.id)).items.length, 1);
    await assert.rejects(library.openItem(course.id, "link-item"), isCourseError("unsafe-item"));

    const sourceTarget = path.join(directory, "source-target.md");
    const sourceLink = path.join(directory, "source-link.md");
    await writeFile(sourceTarget, "source", "utf8");
    await symlink(sourceTarget, sourceLink);
    const beforeImport = await readFile(statePath);
    await assert.rejects(
      library.importFiles(course.id, [sourceLink]),
      isCourseError("not-regular-file"),
    );
    assert.deepEqual(await readFile(statePath), beforeImport);
  });
});

test("mac image items remain visible but unavailable to the Windows text reader", async () => {
  await withLibrary(async ({ library, rootPath }) => {
    const courseID = randomUUID();
    const relativePath = `${COURSE_MATERIALS_DIRECTORY}/图.png`;
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Mac Image Course",
      courseID,
      title: "图像资料",
      items: [{
        ...portableItem("image-item", relativePath),
        kind: "text",
        isNotebookNote: false,
        appearsInMaterials: true,
      }],
    });
    await writeFile(path.join(courseRoot, ...relativePath.split("/")), Buffer.from([
      0x89, 0x50, 0x4e, 0x47,
    ]));

    assert.deepEqual(
      (await library.listCourses()).map((course) => course.id),
      [courseID],
    );
    const detail = await library.detail(courseID);
    assert.equal(detail.items.length, 1);
    assert.equal(detail.items[0].kind, "text");
    assert.equal(detail.items[0].unavailable, true);
    await assert.rejects(
      library.openItem(courseID, "image-item"),
      isCourseError("unsupported-reader-item"),
    );
  });
});

test("an existing mac-style course round-trips unknown fields and lossless revision", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID().toUpperCase();
    const legacyBytes = Buffer.from("# 旧资料\n\n不可丢失。\n", "utf8");
    const legacyDigest = sha256(legacyBytes);
    const legacyRevision = 9_007_199_254_740_993n;
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Mac Course",
      courseID,
      title: "Mac 旧课程",
      revision: legacyRevision,
      items: [
        {
          ...portableItem("legacy-item", `${COURSE_MATERIALS_DIRECTORY}/旧资料.md`),
          contentRevision: 9_007_199_254_740_995n,
          contentDigest: legacyDigest,
          fileByteCount: legacyBytes.byteLength,
          futureItemField: { raw: "keep-item" },
        },
      ],
      extraState: {
        futureStateField: { raw: "keep-state" },
        studySessions: [],
      },
      extraMetadata: { futureMetadataField: "keep-metadata" },
    });
    await writeFile(
      path.join(courseRoot, COURSE_MATERIALS_DIRECTORY, "旧资料.md"),
      legacyBytes,
    );
    const manifestPath = path.join(courseRoot, COURSE_MANIFEST_RELATIVE_PATH);
    const manifestBefore = await readFile(manifestPath);
    const library = new CourseLibrary(rootPath);
    const listed = await library.listCourses();
    assert.equal(listed.length, 1);
    assert.equal(listed[0].id, courseID);
    assert.equal((await library.detail(courseID)).items[0].id, "legacy-item");

    const sourcePath = path.join(directory, "新增.md");
    await writeFile(sourcePath, "# 新增\n", "utf8");
    await library.importFiles(courseID, [sourcePath]);

    assert.deepEqual(await readFile(manifestPath), manifestBefore);
    assert.deepEqual(
      await readFile(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY, "旧资料.md")),
      legacyBytes,
    );
    const roundTripped = await readSwiftObject(
      path.join(courseRoot, COURSE_STATE_RELATIVE_PATH),
    );
    assert.equal(roundTripped.revision, legacyRevision + 1n);
    assert.deepEqual(roundTripped.futureStateField, { raw: "keep-state" });
    assert.deepEqual(roundTripped.studySessions, []);
    const metadata = objectValue(roundTripped.metadata);
    assert.equal(metadata.futureMetadataField, "keep-metadata");
    const items = arrayObjects(roundTripped.items);
    assert.equal(items.length, 2);
    const legacy = items.find((item) => item.itemID === "legacy-item")!;
    assert.equal(legacy.contentRevision, 9_007_199_254_740_995n);
    assert.deepEqual(legacy.futureItemField, { raw: "keep-item" });
  });
});

test("portable v1 Chat history is externalized before the course becomes v2", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID().toUpperCase();
    const sessionID = randomUUID().toUpperCase();
    const messageID = randomUUID().toUpperCase();
    const fixed = new Date("2025-01-02T03:04:05.000Z");
    const createdAt = swiftReferenceSecondsFromDate(fixed);
    const legacyMessage: SwiftJSONObject = {
      id: messageID,
      role: "user",
      text: "不能丢失的旧课程 Chat",
      completionState: "completed",
      sources: [],
      actions: [],
      failureKind: null,
      retryQuestion: null,
      createdAt,
      futureMessageField: { keep: true },
    };
    const legacySession: SwiftJSONObject = {
      id: sessionID,
      title: "旧课程 Chat",
      titleSetByUser: true,
      messages: [legacyMessage],
      summary: "",
      relatedCourseIDs: [courseID],
      focusItemIDs: [],
      flow: { phase: "orient", pinnedByUser: false, suggestedNext: [] },
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
      futureSessionField: { keep: true },
    };
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Legacy Chat Course",
      courseID,
      title: "旧 Chat 课程",
      extraState: {
        schemaVersion: 1,
        studySessions: [legacySession],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const stateBeforeFailedMigration = await readFile(statePath);
    let failedMigrationAttempts = 0;
    const blockedLibrary = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        failedMigrationAttempts += 1;
        throw new Error("migration-blocked");
      },
    });
    const blockedSourcePath = path.join(directory, "迁移失败时不清空.md");
    await writeFile(blockedSourcePath, "# 保留旧 Chat\n", "utf8");
    await assert.rejects(blockedLibrary.importFiles(courseID, [blockedSourcePath]));
    await assert.rejects(blockedLibrary.createNote(courseID, "迁移失败时不创建"));
    assert.equal(failedMigrationAttempts, 2);
    assert.deepEqual(await readFile(statePath), stateBeforeFailedMigration);
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY)),
      [],
    );
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_NOTES_DIRECTORY)),
      [],
    );

    const workspaceDirectory = path.join(directory, "workspace");
    const sessions = await StudySessionStore.open(workspaceDirectory);
    const library = new CourseLibrary({
      rootPath,
      sessionsForCourse: (id) => sessions.listForCourse(id),
      migrateLegacySessions: (id, values, context) =>
        sessions.migrateLegacyCourseSessions(id, values, context),
    });
    const sourcePath = path.join(directory, "新增.md");
    await writeFile(sourcePath, "# 新增\n", "utf8");

    await library.ensureLegacySessionsExternalized(courseID);
    const beforeCourseWrite = await readSwiftObject(statePath);
    assert.equal(beforeCourseWrite.schemaVersion, 1);
    assert.equal(arrayObjects(beforeCourseWrite.studySessions).length, 1);
    assert.deepEqual(
      (await library.detail(courseID)).sessions.flatMap((session) =>
        session.messages.map((message) => message.text)),
      ["不能丢失的旧课程 Chat"],
    );

    // A new library instance has no in-memory migration cache. Repeating the
    // explicit adoption/select preparation must still merge to one Chat.
    const secondLibrary = new CourseLibrary({
      rootPath,
      sessionsForCourse: (id) => sessions.listForCourse(id),
      migrateLegacySessions: (id, values, context) =>
        sessions.migrateLegacyCourseSessions(id, values, context),
    });
    await secondLibrary.ensureLegacySessionsExternalized(courseID);
    await library.importFiles(courseID, [sourcePath]);

    const migrated = await sessions.get(sessionID);
    assert.ok(migrated);
    assert.deepEqual(migrated.messages.map((message) => message.text), [
      "不能丢失的旧课程 Chat",
    ]);
    const state = await readSwiftObject(
      statePath,
    );
    assert.equal(state.schemaVersion, 2);
    assert.deepEqual(state.studySessions, []);

    const workspace = await readSwiftObject(
      path.join(workspaceDirectory, "workspace.json"),
    );
    const metadata = arrayObjects(workspace.studySessions)[0];
    assert.deepEqual(metadata.messages, []);
    assert.equal(metadata.messageCount, 1);
    assert.deepEqual(metadata.futureSessionField, { keep: true });
    const payload = await readSwiftObject(
      path.join(workspaceDirectory, "Sessions", `${sessionID.toLowerCase()}.json`),
    );
    assert.deepEqual(arrayObjects(payload.messages)[0].futureMessageField, {
      keep: true,
    });
    const reopened = await StudySessionStore.open(workspaceDirectory);
    const reopenedSessions = await reopened.listForCourse(courseID);
    assert.equal(reopenedSessions.length, 1);
    assert.deepEqual(reopenedSessions[0].messages.map((message) => message.text), [
      "不能丢失的旧课程 Chat",
    ]);
  });
});

test("a course edit during legacy Chat migration is preserved as a conflict", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(new Date("2025-01-02T03:04:05.000Z"));
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Concurrent Legacy Chat",
      courseID,
      title: "并发迁移",
      extraState: {
        schemaVersion: 1,
        studySessions: [{
          id: randomUUID(),
          title: "旧 Chat",
          messages: [{
            id: randomUUID(),
            role: "user",
            text: "保留并发修改",
            createdAt,
          }],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    let externalBytes = "";
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        const state = await readSwiftObject(statePath);
        externalBytes = stringifySwiftJSON({
          ...state,
          revision: 99,
          futureExternalEdit: { keep: true },
        }, { sortKeys: true });
        await writeFile(statePath, externalBytes, "utf8");
      },
    });
    const sourcePath = path.join(directory, "不应复制.md");
    await writeFile(sourcePath, "# 不应复制\n", "utf8");

    await assert.rejects(
      library.importFiles(courseID, [sourcePath]),
      isCourseError("portable-state-conflict"),
    );
    assert.equal(await readFile(statePath, "utf8"), externalBytes);
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY)),
      [],
    );
  });
});

test("UInt64.max course revision rejects writes before Chat migration or file creation", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Max Revision",
      courseID,
      title: "不可溢出",
      revision: 18_446_744_073_709_551_615n,
      extraState: {
        schemaVersion: 1,
        studySessions: [{
          id: randomUUID(),
          title: "唯一 Chat",
          messages: [{
            id: randomUUID(),
            role: "user",
            text: "不可先外置",
            createdAt,
          }],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const before = await readFile(statePath);
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });
    const sourcePath = path.join(directory, "不应复制.md");
    await writeFile(sourcePath, "# 不应复制\n", "utf8");

    await assert.rejects(
      library.importFiles(courseID, [sourcePath]),
      isCourseError("portable-revision-overflow"),
    );
    await assert.rejects(
      library.createNote(courseID, "不应创建"),
      isCourseError("portable-revision-overflow"),
    );
    assert.equal(migrationCalls, 0);
    assert.deepEqual(await readFile(statePath), before);
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY)),
      [],
    );
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_NOTES_DIRECTORY)),
      [],
    );
  });
});

test("Mac-tolerated v1 compatibility fields normalize without holding Chat", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const profileVariants: Array<(courseID: string) => SwiftJSONObject> = [
      (courseID) => ({ courseID, revision: 0 }),
      (courseID) => ({ courseID, revision: 0, entries: null }),
      (courseID) => ({ courseID, revision: 0, entries: { legacy: true } }),
      (courseID) => ({
        courseID,
        revision: 0,
        entries: [
          {
            id: randomUUID(),
            kind: "concept",
            text: "可解码条目",
            sources: [],
            createdAt,
            updatedAt: createdAt,
          },
          {
            id: randomUUID(),
            kind: "concept",
            text: "缺少 updatedAt 使整个数组回退",
            sources: [],
            createdAt,
          },
        ],
      }),
    ];
    let migrationCalls = 0;

    for (const [index, makeProfile] of profileVariants.entries()) {
      const courseID = randomUUID();
      const sessionID = randomUUID();
      const validRelationID = randomUUID();
      const noteItem = {
        ...portableItem("note-item", `${COURSE_NOTES_DIRECTORY}/笔记.md`),
        appearsInMaterials: false,
      };
      const materialItem = {
        ...portableItem("material-item", `${COURSE_MATERIALS_DIRECTORY}/材料.md`),
        isNotebookNote: false,
        appearsInMaterials: true,
      };
      const dualRoleItem = portableItem(
        "dual-item",
        `${COURSE_MATERIALS_DIRECTORY}/双重角色.md`,
      );
      const courseRoot = await writeMacCourse(rootPath, {
        folderName: `Mac Compatibility ${index}`,
        courseID,
        title: "Mac 可接受状态",
        items: [noteItem, materialItem, dualRoleItem],
        extraState: {
          schemaVersion: 1,
          pendingNoteDrafts: [{
            itemID: "note-item",
            markdown: "",
            baselineContentDigest: null,
          }],
          courseKnowledgeProfile: makeProfile(courseID),
          noteSourceLinks: [
            {
              id: validRelationID,
              noteItemID: "note-item",
              sourceItemID: "material-item",
              createdAt,
            },
            {
              id: randomUUID(),
              noteItemID: "foreign-note",
              sourceItemID: "material-item",
              createdAt,
            },
            {
              id: randomUUID(),
              noteItemID: "dual-item",
              sourceItemID: "dual-item",
              createdAt,
            },
          ],
          resumePoint: {
            courseID,
            materialLocation: {
              itemID: "material-item",
              itemTitle: "材料",
              lastStudiedAt: createdAt,
              visitCount: 1,
            },
            chatID: randomUUID(),
            noteItemID: "note-item",
            savedAt: createdAt,
          },
          studySessions: [{
            id: sessionID,
            title: "缺省空消息 Chat",
            relatedCourseIDs: [courseID],
            createdAt,
            updatedAt: createdAt,
            messageCount: 0,
            // StudySession's custom decoder defaults a missing body to [].
          }],
        },
      });
      const sourcePath = path.join(directory, `新增-${index}.md`);
      await writeFile(sourcePath, `# 新增 ${index}\n`, "utf8");
      const library = new CourseLibrary({
        rootPath,
        migrateLegacySessions: async (_id, sessions, context) => {
          migrationCalls += 1;
          assert.deepEqual(sessions[0].messages, []);
          assert.deepEqual(context.relations, [{
            id: validRelationID,
            noteItemID: "note-item",
            sourceItemID: "material-item",
          }]);
        },
      });

      await library.importFiles(courseID, [sourcePath]);
      const state = await readSwiftObject(
        path.join(courseRoot, COURSE_STATE_RELATIVE_PATH),
      );
      assert.equal(state.schemaVersion, 2);
      assert.deepEqual(state.studySessions, []);
      assert.deepEqual(arrayObjects(state.noteSourceLinks).map((value) => value.id), [
        validRelationID,
      ]);
      assert.equal(state.resumePoint, null);
      assert.deepEqual(objectValue(state.courseKnowledgeProfile).entries, []);
      assert.equal(
        arrayObjects(state.pendingNoteDrafts)[0].markdown,
        "",
      );
    }
    assert.equal(migrationCalls, profileVariants.length * 2);
  });
});

test("a profile Date outside JavaScript range stays fail-closed with zero writes", async () => {
  await withLibrary(async ({ rootPath }) => {
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Unrepresentable Profile Date",
      courseID,
      title: "日期越界保护",
      extraState: {
        schemaVersion: 1,
        courseKnowledgeProfile: {
          courseID,
          revision: 0,
          entries: [{
            id: randomUUID(),
            kind: "concept",
            text: "不能在 JS Date 中表示",
            sources: [],
            createdAt: 1e100,
            updatedAt: createdAt,
          }],
        },
        studySessions: [{
          id: randomUUID(),
          title: "必须保留",
          messages: [{
            id: randomUUID(),
            role: "user",
            text: "唯一 Chat 副本",
            createdAt,
          }],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const before = await readFile(statePath);
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });

    await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
    assert.equal(migrationCalls, 0);
    assert.deepEqual(await readFile(statePath), before);
  });
});

test("invalid v1 metadata and knowledge profiles hold embedded Chat with zero writes", async () => {
  await withLibrary(async ({ rootPath }) => {
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const invalidCases = [
      {
        folderName: "Blank Metadata",
        extraMetadata: { title: "   " },
        profile: null,
      },
      {
        folderName: "Foreign Profile",
        extraMetadata: {},
        profile: {
          courseID: randomUUID(),
          revision: 0,
          entries: [{ id: randomUUID(), text: "合法文本" }],
        },
      },
      {
        folderName: "Duplicate Profile Entry",
        extraMetadata: {},
        profile: null,
      },
    ];
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });

    for (const [index, invalid] of invalidCases.entries()) {
      const courseID = randomUUID();
      const entryID = randomUUID();
      const profile = invalid.folderName === "Duplicate Profile Entry"
        ? {
            courseID,
            revision: 0,
            entries: [
              {
                id: entryID,
                kind: "concept",
                text: "第一项",
                sources: [],
                createdAt,
                updatedAt: createdAt,
              },
              {
                id: entryID.toUpperCase(),
                kind: "concept",
                text: "第二项",
                sources: [],
                createdAt,
                updatedAt: createdAt,
              },
            ],
          }
        : invalid.profile;
      const courseRoot = await writeMacCourse(rootPath, {
        folderName: `${invalid.folderName}-${index}`,
        courseID,
        title: "应被拦截",
        extraMetadata: invalid.extraMetadata,
        extraState: {
          schemaVersion: 1,
          courseKnowledgeProfile: profile,
          studySessions: [{
            id: randomUUID(),
            title: "必须保留",
            messages: [{
              id: randomUUID(),
              role: "user",
              text: "唯一 Chat 副本",
              createdAt,
            }],
            relatedCourseIDs: [courseID],
            createdAt,
            updatedAt: createdAt,
            messageCount: 1,
          }],
        },
      });
      const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
      const before = await readFile(statePath);
      await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
      assert.deepEqual(await readFile(statePath), before);
    }
    assert.equal(migrationCalls, 0);
  });
});

test("non-Codable v1 drafts and profiles hold embedded Chat with zero writes", async () => {
  await withLibrary(async ({ rootPath }) => {
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });

    for (const [index, invalidState] of [
      { pendingNoteDrafts: [42] },
      {
        courseKnowledgeProfile: {
          courseID: randomUUID(),
          entries: [],
        },
      },
    ].entries()) {
      const courseID = randomUUID();
      if (invalidState.courseKnowledgeProfile) {
        invalidState.courseKnowledgeProfile.courseID = courseID;
      }
      const courseRoot = await writeMacCourse(rootPath, {
        folderName: `Non Codable State ${index}`,
        courseID,
        title: "不可解码状态",
        extraState: {
          schemaVersion: 1,
          ...invalidState,
          studySessions: [{
            id: randomUUID(),
            title: "必须保留",
            messages: [{
              id: randomUUID(),
              role: "user",
              text: "唯一 Chat 副本",
              createdAt,
            }],
            relatedCourseIDs: [courseID],
            createdAt,
            updatedAt: createdAt,
            messageCount: 1,
          }],
        },
      });
      const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
      const before = await readFile(statePath);
      await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
      assert.deepEqual(await readFile(statePath), before);
    }
    assert.equal(migrationCalls, 0);
  });
});

test("non-Codable v1 relations, locations, memory, and resume points hold Chat", async () => {
  await withLibrary(async ({ rootPath }) => {
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const noteItem = {
      ...portableItem("note-item", `${COURSE_NOTES_DIRECTORY}/笔记.md`),
      appearsInMaterials: false,
    };
    const materialItem = {
      ...portableItem("material-item", `${COURSE_MATERIALS_DIRECTORY}/材料.md`),
      isNotebookNote: false,
      appearsInMaterials: true,
    };
    const invalidCases: Array<(courseID: string) => SwiftJSONObject> = [
      () => ({
        noteSourceLinks: [{
          id: randomUUID(),
          noteItemID: "note-item",
          sourceItemID: "material-item",
          // `createdAt` is synthesized-Codable and therefore required.
        }],
      }),
      () => ({
        studyLocationsByItemID: {
          "material-item": {
            itemID: "material-item",
            // itemTitle/lastStudiedAt/visitCount are required.
          },
        },
      }),
      (courseID) => ({
        learningMemoryState: {
          scope: { course: { _0: courseID } },
          entries: [],
          // ScopedLearningMemoryState.revision is required UInt64.
        },
      }),
      (courseID) => ({
        resumePoint: {
          courseID,
          materialLocation: null,
          chatID: null,
          noteItemID: null,
          // CourseResumePoint.savedAt is required.
        },
      }),
    ];
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });

    for (const [index, makeInvalidState] of invalidCases.entries()) {
      const courseID = randomUUID();
      const courseRoot = await writeMacCourse(rootPath, {
        folderName: `Invalid Synthesized Shape ${index}`,
        courseID,
        title: "不可解码课程字段",
        items: [noteItem, materialItem],
        extraState: {
          schemaVersion: 1,
          ...makeInvalidState(courseID),
          studySessions: [{
            id: randomUUID(),
            title: "必须保留",
            messages: [{
              id: randomUUID(),
              role: "user",
              text: "唯一 Chat 副本",
              createdAt,
            }],
            relatedCourseIDs: [courseID],
            createdAt,
            updatedAt: createdAt,
            messageCount: 1,
          }],
        },
      });
      const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
      const before = await readFile(statePath);
      await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
      assert.deepEqual(await readFile(statePath), before);
    }
    assert.equal(migrationCalls, 0);
  });
});

test("invalid v1 memory scope and memory provenance hold Chat", async () => {
  await withLibrary(async ({ rootPath }) => {
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });
    for (const kind of ["scope", "provenance"] as const) {
      const courseID = randomUUID();
      const sessionID = randomUUID();
      const messageID = randomUUID();
      const memoryID = randomUUID();
      const courseRoot = await writeMacCourse(rootPath, {
        folderName: `Invalid Context ${kind}`,
        courseID,
        title: "无效上下文",
        extraState: {
          schemaVersion: 1,
          noteSourceLinks: [],
          learningMemoryState: {
            scope: { course: { _0: kind === "scope" ? randomUUID() : courseID } },
            revision: 1,
            entries: [{
              id: memoryID,
              kind: "goal",
              text: "保留记忆",
              evidence: "旧 Chat",
              origin: "userStatement",
              status: "active",
              sessionID: kind === "provenance" ? randomUUID() : sessionID,
              messageID,
              createdAt,
              updatedAt: createdAt,
              revisions: [],
            }],
          },
          studySessions: [{
            id: sessionID,
            title: "必须保留",
            messages: [{
              id: messageID,
              role: "user",
              text: "唯一 Chat 副本",
              createdAt,
            }],
            relatedCourseIDs: [courseID],
            createdAt,
            updatedAt: createdAt,
            messageCount: 1,
          }],
        },
      });
      const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
      const before = await readFile(statePath);
      await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
      assert.deepEqual(await readFile(statePath), before);
    }
    assert.equal(migrationCalls, 0);
  });
});

test("invalid v1 shared item storage holds Chat", async () => {
  await withLibrary(async ({ rootPath }) => {
    const courseID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const invalidItem: SwiftJSONObject = {
      ...portableItem("invalid-shared", `${COURSE_MATERIALS_DIRECTORY}/非法共享.md`),
      storage: {
        kind: "sharedReference",
        sharedRelativePath: "bad",
        expectedContentDigest: null,
      },
      contentDigest: null,
    };
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Invalid Shared Item",
      courseID,
      title: "非法共享条目",
      items: [invalidItem],
      extraState: {
        schemaVersion: 1,
        studySessions: [{
          id: randomUUID(),
          title: "必须保留",
          messages: [{
            id: randomUUID(),
            role: "user",
            text: "唯一 Chat 副本",
            createdAt,
          }],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const before = await readFile(statePath);
    let migrationCalls = 0;
    const library = new CourseLibrary({
      rootPath,
      migrateLegacySessions: async () => {
        migrationCalls += 1;
      },
    });

    assert.deepEqual(await library.listCourses(), []);
    await assert.rejects(library.ensureLegacySessionsExternalized(courseID));
    assert.equal(migrationCalls, 0);
    assert.deepEqual(await readFile(statePath), before);
  });
});

test("a state edit after staging wins the course compare-and-swap", async () => {
  await withLibrary(async ({ library }) => {
    const course = await library.createCourse("提交竞态");
    const statePath = path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH);
    const state = await readSwiftObject(statePath);
    state.futureBlob = "x".repeat(16 * 1024 * 1024);
    await writeFile(statePath, stringifySwiftJSON(state, { sortKeys: true }), "utf8");

    const metadataPath = path.dirname(statePath);
    const abort = new AbortController();
    let externalBytes: string | null = null;
    const externalEdit = (async () => {
      try {
        for await (const event of watch(metadataPath, { signal: abort.signal })) {
          if (!event.filename?.startsWith(".course-state.json.weibei-transaction-")) {
            continue;
          }
          const stagedState = await readSwiftObject(statePath);
          externalBytes = stringifySwiftJSON({
            ...stagedState,
            externalEdit: "MUST_SURVIVE",
          }, { sortKeys: true });
          await writeFile(statePath, externalBytes, "utf8");
          return;
        }
      } catch (error) {
        if (!(error instanceof Error) || error.name !== "AbortError") throw error;
      }
    })();

    try {
      await assert.rejects(
        library.createNote(course.id, "不能覆盖外部编辑"),
        isCourseError("portable-state-conflict"),
      );
      await externalEdit;
      assert.ok(externalBytes);
      assert.equal(await readFile(statePath, "utf8"), externalBytes);
      const finalState = await readSwiftObject(statePath);
      assert.equal(finalState.externalEdit, "MUST_SURVIVE");
      assert.deepEqual(finalState.items, []);
    } finally {
      abort.abort();
      await externalEdit;
    }
  });
});

test("an interrupted state transaction restores its unique displaced baseline", async () => {
  await withLibrary(async ({ library, rootPath }) => {
    const course = await library.createCourse("崩溃恢复");
    const statePath = path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH);
    const stateBytes = await readFile(statePath);
    const transactionPath = path.join(
      path.dirname(statePath),
      ".course-state.json.weibei-transaction-crash-fixture",
    );
    await mkdir(transactionPath);
    await writeFile(path.join(transactionPath, "previous"), stateBytes);
    await writeFile(
      path.join(transactionPath, "transaction.json"),
      JSON.stringify({
        schemaVersion: 1,
        targetFileName: "course-state.json",
        expectedDigest: sha256(stateBytes),
        nextDigest: sha256("unused-next-generation"),
      }),
      "utf8",
    );
    await rm(statePath);

    const reopened = new CourseLibrary(rootPath);
    assert.deepEqual(
      (await reopened.listCourses()).map((value) => value.id),
      [course.id],
    );
    assert.deepEqual(await readFile(statePath), stateBytes);
    assert.deepEqual(await readFile(path.join(transactionPath, "previous")), stateBytes);
  });
});

test("state transaction recovery never overwrites an existing race winner", async () => {
  await withLibrary(async ({ library, rootPath }) => {
    const course = await library.createCourse("恢复竞态赢家");
    const statePath = path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH);
    const baseline = await readFile(statePath);
    const transactionPath = path.join(
      path.dirname(statePath),
      ".course-state.json.weibei-transaction-race-fixture",
    );
    await mkdir(transactionPath);
    await writeFile(path.join(transactionPath, "previous"), baseline);
    await writeFile(
      path.join(transactionPath, "transaction.json"),
      JSON.stringify({
        schemaVersion: 1,
        targetFileName: "course-state.json",
        expectedDigest: sha256(baseline),
        nextDigest: sha256("unused-next-generation"),
      }),
      "utf8",
    );
    const winner = await readSwiftObject(statePath);
    winner.externalWinner = "MUST_SURVIVE";
    const winnerBytes = stringifySwiftJSON(winner, { sortKeys: true });
    await writeFile(statePath, winnerBytes, "utf8");

    const reopened = new CourseLibrary(rootPath);
    assert.equal((await reopened.listCourses()).length, 1);
    assert.equal(await readFile(statePath, "utf8"), winnerBytes);
    assert.deepEqual(await readFile(path.join(transactionPath, "previous")), baseline);
  });
});

test("an observed stale transaction can never roll state back after later commits", async () => {
  await withLibrary(async ({ library, rootPath }) => {
    const course = await library.createCourse("禁止旧事务回滚");
    const statePath = path.join(course.rootPath, COURSE_STATE_RELATIVE_PATH);
    const oldBaseline = await readFile(statePath);
    const transactionPath = path.join(
      path.dirname(statePath),
      ".course-state.json.weibei-transaction-stale-fixture",
    );
    await mkdir(transactionPath);
    await writeFile(path.join(transactionPath, "previous"), oldBaseline);
    await writeFile(
      path.join(transactionPath, "transaction.json"),
      JSON.stringify({
        schemaVersion: 1,
        targetFileName: "course-state.json",
        expectedDigest: sha256(oldBaseline),
        nextDigest: sha256("stale-next-generation"),
      }),
      "utf8",
    );

    const reopened = new CourseLibrary(rootPath);
    const note = await reopened.createNote(course.id, "后来提交");
    assert.ok(note);
    assert.equal(
      await readFile(path.join(transactionPath, "target-observed"), "utf8"),
      "target-observed-v1",
    );
    const laterState = await readSwiftObject(statePath);
    assert.equal(arrayObjects(laterState.items).length, 1);

    await rm(statePath);
    assert.deepEqual(await new CourseLibrary(rootPath).listCourses(), []);
    await assert.rejects(readFile(statePath), isNodeErrorCode("ENOENT"));
    assert.deepEqual(await readFile(path.join(transactionPath, "previous")), oldBaseline);
  });
});

test("a changed non-empty v1 Chat conflicts with its already externalized body", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const messageID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const legacyMessage: SwiftJSONObject = {
      id: messageID,
      role: "user",
      text: "global A",
      createdAt,
    };
    const legacySession: SwiftJSONObject = {
      id: sessionID,
      title: "冲突 Chat",
      messages: [legacyMessage],
      relatedCourseIDs: [courseID],
      createdAt,
      updatedAt: createdAt,
      messageCount: 1,
    };
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Changed Legacy Chat",
      courseID,
      title: "Chat 冲突",
      extraState: {
        schemaVersion: 1,
        studySessions: [legacySession],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const workspaceDirectory = path.join(directory, "workspace-conflict");
    const sessions = await StudySessionStore.open(workspaceDirectory);
    const library = new CourseLibrary({
      rootPath,
      sessionsForCourse: (id) => sessions.listForCourse(id),
      migrateLegacySessions: (id, values, context) =>
        sessions.migrateLegacyCourseSessions(id, values, context),
    });
    await library.ensureLegacySessionsExternalized(courseID);
    const payloadPath = path.join(
      workspaceDirectory,
      "Sessions",
      `${sessionID.toLowerCase()}.json`,
    );
    const globalABefore = await readFile(payloadPath);

    const stateA = await readSwiftObject(statePath);
    const stateBBytes = stringifySwiftJSON({
      ...stateA,
      revision: 1,
      studySessions: [{
        ...legacySession,
        messages: [{ ...legacyMessage, text: "course B" }],
      }],
    }, { sortKeys: true });
    await writeFile(statePath, stateBBytes, "utf8");
    const sourcePath = path.join(directory, "冲突时不复制.md");
    await writeFile(sourcePath, "# 不复制\n", "utf8");

    await assert.rejects(
      library.importFiles(courseID, [sourcePath]),
      /existing-session-body-conflict/,
    );
    assert.equal(await readFile(statePath, "utf8"), stateBBytes);
    assert.deepEqual(await readFile(payloadPath), globalABefore);
    assert.deepEqual(
      (await sessions.get(sessionID))?.messages.map((message) => message.text),
      ["global A"],
    );
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY)),
      [],
    );
  });
});

test("a damaged externalized Chat is revalidated before clearing the v1 copy", async () => {
  await withLibrary(async ({ rootPath, directory }) => {
    const courseID = randomUUID();
    const sessionID = randomUUID();
    const createdAt = swiftReferenceSecondsFromDate(
      new Date("2025-01-02T03:04:05.000Z"),
    );
    const courseRoot = await writeMacCourse(rootPath, {
      folderName: "Damaged External Chat",
      courseID,
      title: "损坏正文保护",
      extraState: {
        schemaVersion: 1,
        studySessions: [{
          id: sessionID,
          title: "唯一 Chat",
          messages: [{
            id: randomUUID(),
            role: "user",
            text: "课程内唯一副本",
            createdAt,
          }],
          relatedCourseIDs: [courseID],
          createdAt,
          updatedAt: createdAt,
          messageCount: 1,
        }],
      },
    });
    const statePath = path.join(courseRoot, COURSE_STATE_RELATIVE_PATH);
    const stateBefore = await readFile(statePath);
    const workspaceDirectory = path.join(directory, "workspace-damaged");
    const sessions = await StudySessionStore.open(workspaceDirectory);
    const library = new CourseLibrary({
      rootPath,
      sessionsForCourse: (id) => sessions.listForCourse(id),
      migrateLegacySessions: (id, values, context) =>
        sessions.migrateLegacyCourseSessions(id, values, context),
    });
    await library.ensureLegacySessionsExternalized(courseID);
    const payloadPath = path.join(
      workspaceDirectory,
      "Sessions",
      `${sessionID.toLowerCase()}.json`,
    );
    await writeFile(payloadPath, "{", "utf8");
    const sourcePath = path.join(directory, "损坏时不复制.md");
    await writeFile(sourcePath, "# 不复制\n", "utf8");

    await assert.rejects(
      library.importFiles(courseID, [sourcePath]),
      /existing-session-payload-invalid/,
    );
    assert.deepEqual(await readFile(statePath), stateBefore);
    assert.equal(await readFile(payloadPath, "utf8"), "{");
    assert.deepEqual(
      await readdir(path.join(courseRoot, COURSE_MATERIALS_DIRECTORY)),
      [],
    );
  });
});

test("a failed batch import removes files that were never registered", async () => {
  await withLibrary(async ({ library, directory }) => {
    const course = await library.createCourse("批量回滚");
    const good = path.join(directory, "先复制.md");
    const unsupported = path.join(directory, "后失败.bin");
    await Promise.all([
      writeFile(good, "# 临时文件\n", "utf8"),
      writeFile(unsupported, "unsupported", "utf8"),
    ]);

    await assert.rejects(
      library.importFiles(course.id, [good, unsupported]),
      isCourseError("unsupported-file"),
    );
    assert.deepEqual(
      await readdir(path.join(course.rootPath, COURSE_MATERIALS_DIRECTORY)),
      [],
    );
    assert.deepEqual((await library.detail(course.id)).items, []);
  });
});

interface LibraryFixture {
  directory: string;
  rootPath: string;
  library: CourseLibrary;
}

async function withLibrary(
  operation: (fixture: LibraryFixture) => Promise<void>,
): Promise<void> {
  const directory = await mkdtemp(path.join(os.tmpdir(), "weibei-course-library-"));
  const rootPath = path.join(directory, "library");
  await mkdir(rootPath);
  try {
    await operation({
      directory,
      rootPath,
      library: new CourseLibrary(rootPath),
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

interface MacCourseOptions {
  folderName: string;
  courseID: string;
  title: string;
  revision?: number | bigint;
  items?: SwiftJSONObject[];
  extraState?: SwiftJSONObject;
  extraMetadata?: SwiftJSONObject;
}

async function writeMacCourse(
  libraryRoot: string,
  options: MacCourseOptions,
): Promise<string> {
  const root = path.join(libraryRoot, options.folderName);
  await Promise.all([
    mkdir(path.join(root, ".weibei"), { recursive: true }),
    mkdir(path.join(root, COURSE_MATERIALS_DIRECTORY), { recursive: true }),
    mkdir(path.join(root, COURSE_NOTES_DIRECTORY), { recursive: true }),
  ]);
  const fixed = new Date("2025-01-02T03:04:05.000Z");
  const manifest = { courseID: options.courseID, schemaVersion: 1 };
  const state: SwiftJSONObject = {
    courseID: options.courseID,
    schemaVersion: 2,
    revision: options.revision ?? 0,
    savedAt: swiftReferenceSecondsFromDate(fixed),
    metadata: {
      title: options.title,
      colorIndex: 1,
      createdAt: swiftReferenceSecondsFromDate(fixed),
      updatedAt: swiftReferenceSecondsFromDate(fixed),
      ...options.extraMetadata,
    },
    items: options.items ?? [],
    studySessions: [],
    learningMemoryState: null,
    courseKnowledgeProfile: null,
    noteSourceLinks: [],
    studyLocationsByItemID: {},
    resumePoint: null,
    pendingNoteDrafts: [],
    ...options.extraState,
  };
  await Promise.all([
    writeFile(
      path.join(root, COURSE_MANIFEST_RELATIVE_PATH),
      stringifySwiftJSON(manifest, { sortKeys: true }),
      "utf8",
    ),
    writeFile(
      path.join(root, COURSE_STATE_RELATIVE_PATH),
      stringifySwiftJSON(state, { sortKeys: true }),
      "utf8",
    ),
  ]);
  return root;
}

function portableItem(itemID: string, courseRelativePath: string): SwiftJSONObject {
  const fixed = new Date("2025-01-02T03:04:05.000Z");
  return {
    itemID,
    title: path.basename(courseRelativePath, path.extname(courseRelativePath)),
    kind: "markdown",
    isNotebookNote: true,
    appearsInMaterials: true,
    courseRelativePath,
    storage: { kind: "courseOwned" },
    contentRevision: 1,
    contentDigest: null,
    fileByteCount: null,
    fileModificationTimeNanoseconds: null,
    membershipCreatedAt: swiftReferenceSecondsFromDate(fixed),
  };
}

async function readSwiftObject(filePath: string): Promise<SwiftJSONObject> {
  return objectValue(parseSwiftJSON(await readFile(filePath, "utf8")));
}

function objectValue(value: unknown): SwiftJSONObject {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  return value as SwiftJSONObject;
}

function arrayObjects(value: unknown): SwiftJSONObject[] {
  assert.ok(Array.isArray(value));
  return value.map(objectValue);
}

function assertSwiftDate(value: unknown): void {
  assert.ok(typeof value === "number" || typeof value === "bigint");
  assert.ok(Number.isFinite(dateFromSwiftReferenceSeconds(value).getTime()));
}

function isCourseError(code: string): (error: unknown) => boolean {
  return (error) => error instanceof CourseLibraryError && error.code === code;
}

function isNodeErrorCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof Error && "code" in error && error.code === code;
}
