import Foundation
import WeiBeiCore

enum CourseProjectRootSelfCheck {
    @MainActor
    static func run() throws {
        try libraryGrantPersistsAndBalancesSecurityScope()
        try libraryCannotEqualOrSitInsideRegisteredCourse()
        try deniedSecurityScopeKeepsCourseUnavailable()
        try movedLibraryIntoWorkspaceIsRejectedOnRestore()
        try newCourseCreatesAtomicProjectAndManifest()
        try stagedAndWorkspaceFailuresLeaveNoGhostCourse()
        try failedAdoptionRollsBackOnlyItsOwnMetadata()
        try foreignWritesPreventRollbackDeletion()
        try dangerousAndOverlappingRootsWriteNothing()
        try adoptingExistingFolderPreservesVisibleContentsAndIsIdempotent()
        try repeatedAdoptionRefreshesTrackingAndOwnership()
        try failedReadoptionRestoresPreviousCourseAndScope()
        try damagedMetadataIsNotOverwritten()
        try movedLibraryCourseRestoresTheSameIdentity()
        try legacyCourseSnapshotStillDecodes()
    }

    @MainActor
    private static func libraryCannotEqualOrSitInsideRegisteredCourse() throws {
        for nested in [false, true] {
            let fixture = try Fixture(name: nested ? "library-inside-course" : "library-equals-course")
            defer { fixture.remove() }
            let courseRoot = try fixture.makeDirectory("外部课程")
            let proposedLibrary = nested
                ? try fixture.makeDirectory("外部课程/资料库")
                : courseRoot
            let store = makeStore(fixture: fixture)
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "外部课程")

            try expectFailure(nested ? "资料库位于课程内" : "资料库等于课程") {
                try store.configureCourseLibrary(at: proposedLibrary)
            }
            try check(store.courseLibraryRootURL == nil, "非法资料库仍被配置")
            try check(store.course(withID: courseID) != nil, "拒绝资料库时误删课程")
        }
    }

    @MainActor
    private static func foreignWritesPreventRollbackDeletion() throws {
        do {
            let fixture = try Fixture(name: "foreign-create-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let target = library.appendingPathComponent("并发课程", isDirectory: true)
            var injectForeignWrite = false
            let store = makeStore(
                fixture: fixture,
                workspaceWriter: { data, url in
                    if injectForeignWrite {
                        try Data("用户并发写入".utf8).write(
                            to: target.appendingPathComponent("foreign.txt")
                        )
                        throw CheckError.injectedFailure
                    }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            injectForeignWrite = true

            try expectFailure("新课程并发写入") {
                try store.createCourse(title: "并发课程", at: target)
            }
            try check(
                try String(contentsOf: target.appendingPathComponent("foreign.txt"), encoding: .utf8)
                    == "用户并发写入",
                "回滚误删了新课程根里的用户并发内容"
            )
            try check(store.courses.isEmpty, "并发保存失败后留下幽灵 Course")
        }

        do {
            let fixture = try Fixture(name: "foreign-adopt-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let external = try fixture.makeDirectory("已有课程")
            var injectForeignWrite = false
            let store = makeStore(
                fixture: fixture,
                workspaceWriter: { data, url in
                    if injectForeignWrite {
                        try Data("用户 metadata".utf8).write(
                            to: external.appendingPathComponent(".weibei/foreign.txt")
                        )
                        throw CheckError.injectedFailure
                    }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            injectForeignWrite = true

            try expectFailure("接管 metadata 并发写入") {
                try store.adoptCourseFolder(at: external, title: "已有课程")
            }
            try check(
                try String(
                    contentsOf: external.appendingPathComponent(".weibei/foreign.txt"),
                    encoding: .utf8
                ) == "用户 metadata",
                "回滚误删了 .weibei 里的用户并发内容"
            )
            try check(store.courses.isEmpty, "接管并发保存失败后留下幽灵 Course")
        }

        do {
            let fixture = try Fixture(name: "foreign-after-fingerprint")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let target = library.appendingPathComponent("竞态课程", isDirectory: true)
            var failWorkspaceWrite = false
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard stage == .beforeOwnedRollbackCleanup else { return }
                    try Data("检查后写入".utf8).write(
                        to: target.appendingPathComponent("after-check.txt")
                    )
                },
                workspaceWriter: { data, url in
                    if failWorkspaceWrite { throw CheckError.injectedFailure }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            failWorkspaceWrite = true

            try expectFailure("指纹核验后的并发写入") {
                try store.createCourse(title: "竞态课程", at: target)
            }
            try check(
                try String(
                    contentsOf: target.appendingPathComponent("after-check.txt"),
                    encoding: .utf8
                ) == "检查后写入",
                "空目录收口误删了指纹核验后出现的文件"
            )
            try check(store.courses.isEmpty, "指纹核验后的失败留下幽灵 Course")
        }
    }

    @MainActor
    private static func repeatedAdoptionRefreshesTrackingAndOwnership() throws {
        do {
            let fixture = try Fixture(name: "repeat-adopt-refresh")
            defer { fixture.remove() }
            let oldRoot = try fixture.makeDirectory("旧位置")
            var store: WorkspaceStore? = makeStore(fixture: fixture)
            let courseID = try require(
                store?.adoptCourseFolder(at: oldRoot, title: "原课程名"),
                "首次接管没有课程 ID"
            )
            try check(store?.flushPendingWorkspaceSave() == true, "移动前没有保存课程")
            store = nil

            let movedRoot = fixture.root.appendingPathComponent("新位置", isDirectory: true)
            try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
            var allowAccess = false
            var starts = 0
            store = makeStore(
                fixture: fixture,
                startAccessing: { _ in starts += 1; return allowAccess },
                bookmarkResolver: { _ in
                    CourseProjectResolvedBookmark(url: movedRoot, isStale: true)
                }
            )
            try check(store?.courseRootURL(for: courseID) == nil, "授权失败前课程不应可用")
            try check(store?.courseRootUnavailableReason(for: courseID) != nil, "授权失败没有 unavailable")
            allowAccess = true

            let repeatedID = try require(
                store?.adoptCourseFolder(at: movedRoot, title: "不应覆盖标题"),
                "重复接管没有课程 ID"
            )
            let refreshed = try require(store?.course(withID: courseID), "重复接管后课程丢失")
            try check(repeatedID == courseID, "重复接管改变了 Course ID")
            try check(refreshed.title == "原课程名", "重复接管错误覆盖课程标题")
            try check(refreshed.sourceRootPath == movedRoot.canonicalFileURL.path, "重复接管没有刷新路径")
            try check(store?.courseRootURL(for: courseID) == movedRoot.canonicalFileURL, "重复接管没有恢复可用根")
            try check(store?.courseRootUnavailableReason(for: courseID) == nil, "重复接管没有清除 unavailable")
            try check(starts == 2, "重复接管没有重新建立 security scope")
        }

        do {
            let fixture = try Fixture(name: "repeat-adopt-relative")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("未来资料库")
            let courseRoot = try fixture.makeDirectory("未来资料库/课程")
            var stops = 0
            let store = makeStore(
                fixture: fixture,
                stopAccessing: { _ in stops += 1 }
            )
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "课程")
            try store.configureCourseLibrary(at: library)
            let repeatedID = try store.adoptCourseFolder(at: courseRoot, title: "不改名")
            let converted = try require(store.course(withID: courseID), "库内转换后课程丢失")

            try check(repeatedID == courseID, "库内重复接管改变了 Course ID")
            try check(converted.title == "课程", "库内重复接管覆盖了标题")
            try check(converted.sourceRootRelativePath == "课程", "库内课程没有转成相对引用")
            try check(converted.sourceRootPath == nil, "库内课程仍保留绝对路径真相")
            try check(converted.sourceRootBookmarkData == nil, "库内课程仍保留独立授权")
            try check(stops == 1, "库内转换没有释放旧外部 security scope")
        }

        do {
            let fixture = try Fixture(name: "repeat-adopt-replaced-inode")
            defer { fixture.remove() }
            let courseRoot = try fixture.makeDirectory("被替换课程")
            let store = makeStore(fixture: fixture)
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "原课程")
            let originalIdentity = store.course(withID: courseID)?.sourceRootIdentity
            let manifestData = try Data(
                contentsOf: courseRoot.appendingPathComponent(".weibei/course.json")
            )

            try FileManager.default.removeItem(at: courseRoot)
            try FileManager.default.createDirectory(
                at: courseRoot.appendingPathComponent(".weibei", isDirectory: true),
                withIntermediateDirectories: true
            )
            try manifestData.write(
                to: courseRoot.appendingPathComponent(".weibei/course.json")
            )

            try expectFailure("同路径不同 inode") {
                try store.adoptCourseFolder(at: courseRoot, title: "替换目录")
            }
            try check(
                store.course(withID: courseID)?.sourceRootIdentity == originalIdentity,
                "同路径不同 inode 被静默改绑"
            )
            try check(
                store.course(withID: courseID)?.title == "原课程",
                "拒绝不同 inode 时改动了课程标题"
            )
        }
    }

    @MainActor
    private static func failedReadoptionRestoresPreviousCourseAndScope() throws {
        let fixture = try Fixture(name: "repeat-adopt-save-failure")
        defer { fixture.remove() }
        let oldRoot = try fixture.makeDirectory("旧位置")
        var starts = 0
        var stops = 0
        var failWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 },
            workspaceWriter: { data, url in
                if failWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        let courseID = try store.adoptCourseFolder(at: oldRoot, title: "原课程")
        let previousCourse = try require(store.course(withID: courseID), "首次接管没有课程")
        let previousResolvedRoot = store.courseRootURL(for: courseID)

        let movedRoot = fixture.root.appendingPathComponent("新位置", isDirectory: true)
        try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
        failWorkspaceWrite = true
        try expectFailure("重复接管保存失败") {
            try store.adoptCourseFolder(at: movedRoot, title: "不应改名")
        }

        try check(store.course(withID: courseID) == previousCourse, "保存失败没有恢复旧 Course")
        try check(
            store.courseRootURL(for: courseID) == previousResolvedRoot,
            "保存失败没有恢复旧 resolved root"
        )
        try check(
            store.courseRootUnavailableReason(for: courseID) == nil,
            "保存失败凭空改变了旧 unavailable 状态"
        )
        try check(starts == 2, "重复接管没有取得新 scope")
        try check(stops == 1, "保存失败没有只释放新 scope")
    }

    @MainActor
    private static func failedAdoptionRollsBackOnlyItsOwnMetadata() throws {
        let fixture = try Fixture(name: "adopt-save-failure")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("已有课程")
        try Data("不能改动的原稿".utf8).write(to: external.appendingPathComponent("原稿.txt"))
        let before = try external.visibleFileSnapshot()
        var shouldFailWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            workspaceWriter: { data, url in
                if shouldFailWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        try store.configureCourseLibrary(at: library)
        shouldFailWorkspaceWrite = true

        try expectFailure("接管 workspace 保存") {
            try store.adoptCourseFolder(at: external, title: "已有课程")
        }
        try check(
            !external.appendingPathComponent(".weibei").exists,
            "接管保存失败后没有回滚自己创建的 metadata"
        )
        try check(
            try external.visibleFileSnapshot() == before,
            "接管保存失败时改动了原有可见文件"
        )
        try check(store.courses.isEmpty, "接管保存失败后留下幽灵 Course")
    }

    @MainActor
    private static func movedLibraryIntoWorkspaceIsRejectedOnRestore() throws {
        let fixture = try Fixture(name: "dangerous-library-restore")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        try check(store?.flushPendingWorkspaceSave() == true, "危险搬移测试前没有保存")
        store = nil

        let movedLibrary = fixture.workspaceDirectory
            .appendingPathComponent("课程资料库", isDirectory: true)
        try FileManager.default.moveItem(at: library, to: movedLibrary)
        var stops = 0
        store = makeStore(
            fixture: fixture,
            stopAccessing: { _ in stops += 1 },
            bookmarkResolver: { _ in
                CourseProjectResolvedBookmark(url: movedLibrary, isStale: true)
            }
        )
        try check(store?.courseLibraryRootURL == nil, "危险位置的资料库在重开后仍被接管")
        try check(store?.courseLibraryUnavailableReason != nil, "危险资料库恢复没有报告原因")
        try check(stops == 1, "拒绝危险资料库后没有成对停止授权")
    }

    @MainActor
    private static func deniedSecurityScopeKeepsCourseUnavailable() throws {
        let fixture = try Fixture(name: "scope-denied")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let target = library.appendingPathComponent("课程", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(store?.createCourse(title: "课程", at: target), "没有课程 ID")
        try check(store?.flushPendingWorkspaceSave() == true, "授权拒绝测试前没有保存")
        store = nil

        var stops = 0
        store = makeStore(
            fixture: fixture,
            startAccessing: { _ in false },
            stopAccessing: { _ in stops += 1 }
        )
        try check(store?.courseLibraryRootPath != nil, "授权失效时错误删除了资料库记录")
        try check(store?.courseLibraryRootURL == nil, "授权失败时仍把资料库标成可访问")
        try check(store?.courseLibraryUnavailableReason != nil, "授权失败时没有报告资料库 unavailable")
        try check(store?.course(withID: courseID) != nil, "授权失效时错误删除了课程")
        try check(store?.courseRootURL(for: courseID) == nil, "授权失败时仍把课程标成可访问")
        try check(store?.courseRootUnavailableReason(for: courseID) != nil, "授权失败时没有报告 unavailable")
        store = nil
        try check(stops == 0, "startAccessing 失败后错误调用了 stopAccessing")
    }

    @MainActor
    private static func libraryGrantPersistsAndBalancesSecurityScope() throws {
        let fixture = try Fixture(name: "library-grant")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        var starts = 0
        var stops = 0

        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 }
        )
        try store?.configureCourseLibrary(at: library)
        try check(store?.courseLibraryRootURL == library.canonicalFileURL, "资料库配置后没有可访问的真实根")
        try check(starts == 1 && stops == 0, "资料库授权没有在解析书签后开始")
        try check(store?.flushPendingWorkspaceSave() == true, "资料库授权没有保存")
        store = nil
        try check(stops == 1, "资料库授权结束时没有成对停止")

        store = makeStore(
            fixture: fixture,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 }
        )
        try check(store?.courseLibraryRootURL == library.canonicalFileURL, "重开后没有恢复资料库授权")
        try check(starts == 2, "重开后没有重新开始资料库授权")
        store = nil
        try check(stops == 2, "重开后的资料库授权没有成对停止")
    }

    @MainActor
    private static func newCourseCreatesAtomicProjectAndManifest() throws {
        let fixture = try Fixture(name: "new-course")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let target = library.appendingPathComponent("货币金融学", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)

        let courseID = try require(store?.createCourse(title: "货币金融学", at: target), "没有返回课程 ID")
        let course = try require(store?.course(withID: courseID), "没有保存课程记录")
        try check(course.sourceRootRelativePath == "货币金融学", "资料库内课程没有保存相对根")
        try check(course.sourceRootPath == nil, "资料库内课程不应保存绝对根作为真相")
        try check(course.sourceRootBookmarkData == nil, "资料库内课程错误地保存了独立授权")
        try check(course.sourceRootIdentity != nil, "课程根没有稳定文件身份")
        for name in ["文稿", "笔记", ".weibei"] {
            try check(target.appendingPathComponent(name).isDirectory, "新课程缺少 \(name) 目录")
        }
        let manifest = try CourseProjectManifest.read(
            from: target.appendingPathComponent(".weibei/course.json")
        )
        try check(manifest.courseID == courseID, "课程 manifest 与课程 ID 不一致")
        try check(manifest.schemaVersion == CourseProjectManifest.currentSchemaVersion, "课程 manifest 版本错误")
        try check(store?.flushPendingWorkspaceSave() == true, "新课程没有保存")
        store = nil

        store = makeStore(fixture: fixture)
        try check(store?.courseRootURL(for: courseID) == target.canonicalFileURL, "重开后没有恢复课程根")
        try check(store?.course(withID: courseID)?.sourceRootBookmarkData == nil, "重开后课程错误地产生独立授权")
    }

    @MainActor
    private static func stagedAndWorkspaceFailuresLeaveNoGhostCourse() throws {
        for stage in [CourseProjectMutationStage.afterStagingDirectory, .beforeManifestWrite, .beforeAtomicPlacement] {
            let fixture = try Fixture(name: "stage-\(stage.rawValue)")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let target = library.appendingPathComponent("失败课程", isDirectory: true)
            let store = makeStore(
                fixture: fixture,
                mutationHook: { currentStage in
                    if currentStage == stage { throw CheckError.injectedFailure }
                }
            )
            try store.configureCourseLibrary(at: library)
            try expectFailure("阶段 \(stage.rawValue)") { try store.createCourse(title: "失败课程", at: target) }
            try check(!target.exists, "阶段失败后留下了半成品课程目录")
            try check(store.courses.isEmpty, "阶段失败后留下了幽灵 Course")
            try check(
                try library.stagingChildren().isEmpty,
                "阶段 \(stage.rawValue) 失败后留下了 staging 目录"
            )
        }

        let fixture = try Fixture(name: "workspace-save-failure")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let target = library.appendingPathComponent("保存失败课程", isDirectory: true)
        var shouldFailWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            workspaceWriter: { data, url in
                if shouldFailWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        try store.configureCourseLibrary(at: library)
        shouldFailWorkspaceWrite = true
        try expectFailure("workspace 保存") { try store.createCourse(title: "保存失败课程", at: target) }
        try check(!target.exists, "workspace 保存失败后没有回滚课程目录")
        try check(store.courses.isEmpty, "workspace 保存失败后没有回滚内存 Course")
        let reopened = makeStore(fixture: fixture)
        try check(reopened.courses.isEmpty, "workspace 保存失败后磁盘出现幽灵 Course")
    }

    @MainActor
    private static func dangerousAndOverlappingRootsWriteNothing() throws {
        let fixture = try Fixture(name: "root-guards")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let firstRoot = library.appendingPathComponent("经济学", isDirectory: true)
        _ = try store.createCourse(title: "经济学", at: firstRoot)

        let aliasParent = library.appendingPathComponent("课程别名", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: firstRoot)
        let before = try library.relativeEntries()
        try expectFailure("资料库本身") { try store.createCourse(title: "资料库本身", at: library) }
        try expectFailure("嵌套课程") {
            try store.createCourse(
                title: "嵌套课程",
                at: firstRoot.appendingPathComponent("嵌套课程", isDirectory: true)
            )
        }
        try expectFailure("符号链接逃逸") {
            try store.createCourse(
                title: "符号链接逃逸",
                at: aliasParent.appendingPathComponent("逃逸课程", isDirectory: true)
            )
        }
        try expectFailure("系统根") { try store.adoptCourseFolder(at: URL(fileURLWithPath: "/"), title: "根目录") }
        try expectFailure("主目录") {
            try store.adoptCourseFolder(
                at: FileManager.default.homeDirectoryForCurrentUser,
                title: "主目录"
            )
        }
        let after = try library.relativeEntries()
        try check(before == after, "危险或重叠根检查发生在写盘之后")
        try check(store.courses.count == 1, "危险或重叠根产生了额外 Course")
    }

    @MainActor
    private static func adoptingExistingFolderPreservesVisibleContentsAndIsIdempotent() throws {
        let fixture = try Fixture(name: "adopt")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("已有课程")
        try Data("原始讲义".utf8).write(to: external.appendingPathComponent("第一讲.txt"))
        let nested = try fixture.makeDirectory("已有课程/旧资料")
        try Data([0, 1, 2, 3]).write(to: nested.appendingPathComponent("图像.bin"))
        let before = try external.visibleFileSnapshot()
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)

        let courseID = try store.adoptCourseFolder(at: external, title: "已有课程")
        let after = try external.visibleFileSnapshot()
        try check(
            before == after,
            "接管课程改变了已有可见文件的哈希或层级：前 \(before.keys.sorted())，后 \(after.keys.sorted())"
        )
        let course = try require(store.course(withID: courseID), "接管后没有课程记录")
        try check(course.sourceRootRelativePath == nil, "外部课程错误地使用资料库相对根")
        try check(course.sourceRootBookmarkData != nil, "外部课程没有自己的授权")

        let repeatedID = try store.adoptCourseFolder(at: external, title: "不会覆盖原名")
        try check(repeatedID == courseID, "重复接管没有返回同一个 Course")
        try check(store.courses.count == 1, "重复接管创建了重复 Course")
    }

    @MainActor
    private static func damagedMetadataIsNotOverwritten() throws {
        let fixture = try Fixture(name: "damaged-metadata")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("损坏课程")
        let metadata = try fixture.makeDirectory("损坏课程/.weibei")
        let manifestURL = metadata.appendingPathComponent("course.json")
        let original = Data("{not-json".utf8)
        try original.write(to: manifestURL)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)

        try expectFailure("损坏 metadata") { try store.adoptCourseFolder(at: external, title: "损坏课程") }
        try check(try Data(contentsOf: manifestURL) == original, "接管覆盖了未知或损坏的 .weibei")
        try check(store.courses.isEmpty, "损坏 metadata 仍产生了 Course")
    }

    @MainActor
    private static func movedLibraryCourseRestoresTheSameIdentity() throws {
        let fixture = try Fixture(name: "move-recovery")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let oldRoot = library.appendingPathComponent("旧课程名", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(store?.createCourse(title: "课程", at: oldRoot), "没有课程 ID")
        let identity = store?.course(withID: courseID)?.sourceRootIdentity
        try check(store?.flushPendingWorkspaceSave() == true, "移动前没有保存")
        store = nil

        let movedRoot = library.appendingPathComponent("新课程名", isDirectory: true)
        try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
        store = makeStore(fixture: fixture)
        try check(store?.courses.count == 1, "移动恢复创建或丢失了 Course")
        try check(store?.course(withID: courseID)?.sourceRootIdentity == identity, "移动恢复改变了课程身份")
        try check(store?.courseRootURL(for: courseID) == movedRoot.canonicalFileURL, "没有恢复同卷移动后的课程根")
        try check(store?.course(withID: courseID)?.sourceRootRelativePath == "新课程名", "没有更新移动后的相对根")
    }

    @MainActor
    private static func legacyCourseSnapshotStillDecodes() throws {
        let fixture = try Fixture(name: "legacy-snapshot")
        defer { fixture.remove() }
        let legacyID = UUID()
        let legacyCourse = Course(id: legacyID, title: "旧课程", sourceRootPath: "/tmp/旧课程")
        let snapshot = PersistedWorkspace(courses: [legacyCourse], activeCourseID: legacyID)
        var object = try require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any],
            "旧快照编码不是对象"
        )
        if var courses = object["courses"] as? [[String: Any]], !courses.isEmpty {
            courses[0].removeValue(forKey: "sourceRootRelativePath")
            courses[0].removeValue(forKey: "sourceRootIdentity")
            courses[0].removeValue(forKey: "sourceRootBookmarkData")
            object["courses"] = courses
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: fixture.workspaceDirectory.appendingPathComponent("workspace.json"), options: [.atomic])

        let store = makeStore(fixture: fixture)
        try check(store.course(withID: legacyID)?.title == "旧课程", "旧 Course 快照无法解码")
    }

    @MainActor
    private static func makeStore(
        fixture: Fixture,
        startAccessing: @escaping (URL) -> Bool = { _ in true },
        stopAccessing: @escaping (URL) -> Void = { _ in },
        mutationHook: @escaping (CourseProjectMutationStage) throws -> Void = { _ in },
        bookmarkResolver: ((Data) -> CourseProjectResolvedBookmark?)? = nil,
        workspaceWriter: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: [.atomic])
        }
    ) -> WorkspaceStore {
        WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            courseRootBookmarkMaker: { Data($0.canonicalFileURL.path.utf8) },
            courseRootBookmarkResolver: bookmarkResolver ?? { data in
                    guard let path = String(data: data, encoding: .utf8) else { return nil }
                    return CourseProjectResolvedBookmark(
                        url: URL(fileURLWithPath: path).canonicalFileURL,
                        isStale: false
                    )
                },
            courseSecurityScopeStarter: startAccessing,
            courseSecurityScopeStopper: stopAccessing,
            courseProjectMutationHook: mutationHook,
            workspaceSnapshotWriter: workspaceWriter
        )
    }

    private static func expectFailure(_ label: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
            throw CheckError.expectedFailure(label)
        } catch CheckError.expectedFailure(let label) {
            throw CheckError.expectedFailure(label)
        } catch {
            return
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckError.failed(message) }
        return value
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckError.failed(message) }
    }

    private enum CheckError: LocalizedError {
        case failed(String)
        case expectedFailure(String)
        case injectedFailure

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            case .expectedFailure(let label): "\(label)：本应失败的操作成功了"
            case .injectedFailure: "测试注入失败"
            }
        }
    }

    private struct Fixture {
        let root: URL
        let workspaceDirectory: URL

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-course-root-\(name)-\(UUID().uuidString)", isDirectory: true)
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        }

        func makeDirectory(_ relativePath: String) throws -> URL {
            let url = root.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private extension URL {
    var canonicalFileURL: URL {
        resolvingSymlinksInPath().standardizedFileURL
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var isDirectory: Bool {
        var value: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &value) && value.boolValue
    }

    func stagingChildren() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { $0.hasPrefix(".weibei-course-staging-") }
            .sorted()
    }

    func relativeEntries() throws -> [String] {
        let rootPath = canonicalFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL else { return nil }
            return String(url.canonicalFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }.sorted()
    }

    func visibleFileSnapshot() throws -> [String: Data] {
        let rootPath = canonicalFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return [:]
        }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            let relativePath = String(url.canonicalFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relativePath == ".weibei" || relativePath.hasPrefix(".weibei/") {
                enumerator.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                result[relativePath] = try Data(contentsOf: url)
            }
        }
        return result
    }
}
