import Foundation

@MainActor
extension WorkspaceStore {
    /// 首帧之后才做的启动清理：孤儿事务、过期 pending 文件、sanitize/migrate。
    /// 安全自检仍同步跑完，避免测试在 init 返回后读到半迁移状态。
    func completeDeferredLaunchHousekeeping(
        restoredCourseProjectRoots: Bool,
        restoredPortableCourseStates: Bool,
        resolvedImportedFileBookmarks: Bool,
        migratedImportedItemIdentities: Bool,
        needsPortableCourseStateBootstrap: Bool,
        recoveredInterruptedAgentReply: Bool,
        needsSelectionAskThreadsWorkspaceMigration: Bool
    ) {
        // S3：不再从 journal 恢复未完成操作；仅静默清理残留事务目录。
        let recoveredCourseTrash = silentlyCleanupOrphanCourseTransactions()
        try? FileManager.default.removeItem(
            at: workspaceDirectory.appendingPathComponent("pending-notebook-rename.json")
        )
        try? FileManager.default.removeItem(
            at: workspaceDirectory.appendingPathComponent("pending-course-removal.json")
        )
        let migratedStudyLocationTitles = refreshStudyLocationReferenceTitles()
        let sanitizedNoteSourceLinks = sanitizeNoteSourceLinks()
        let sanitizedCourseLibrary = sanitizeCourseLibrary()
        let migratedStudySessionScopes = migrateLegacyStudySessionScopes()
        let migratedLearningMemoryScopes = migrateLegacyLearningMemoryScopes()
        let sanitizedCourseResumePoints = sanitizeCourseResumePoints()
        let initializedCourseKnowledgeProfiles = ensureCourseKnowledgeProfiles()
        courseDocumentSearchIndex.synchronize(allItems)
        if noteSourceLinksMigrationVersion < 1 {
            migrateNoteSourceLinksFromMarkdown()
            noteSourceLinksMigrationVersion = 1
            save()
        } else if resolvedImportedFileBookmarks
                    || migratedImportedItemIdentities
                    || migratedStudyLocationTitles
                    || sanitizedNoteSourceLinks
                    || sanitizedCourseLibrary
                    || migratedStudySessionScopes
                    || migratedLearningMemoryScopes
                    || sanitizedCourseResumePoints
                    || restoredCourseProjectRoots
                    || restoredPortableCourseStates
                    || recoveredCourseTrash
                    || initializedCourseKnowledgeProfiles
                    || needsPortableCourseStateBootstrap
                    || recoveredInterruptedAgentReply
                    || needsSelectionAskThreadsWorkspaceMigration
                    || sessionMessagePersistence.needsWorkspacePersist {
            save()
        }
    }
}
