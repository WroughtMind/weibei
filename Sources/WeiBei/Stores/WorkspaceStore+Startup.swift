import Foundation

@MainActor
extension WorkspaceStore {
    /// 首帧之后清理孤儿事务并核对工作区状态。
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
        let migratedStudyLocationTitles = refreshStudyLocationReferenceTitles()
        let sanitizedNoteSourceLinks = sanitizeNoteSourceLinks()
        let sanitizedCourseLibrary = sanitizeCourseLibrary()
        let migratedStudySessionScopes = migrateLegacyStudySessionScopes()
        let migratedLearningMemoryScopes = migrateLegacyLearningMemoryScopes()
        let sanitizedCourseResumePoints = sanitizeCourseResumePoints()
        let initializedCourseKnowledgeProfiles = ensureCourseKnowledgeProfiles()
        courseDocumentSearchIndex.synchronize(allItems)
        if resolvedImportedFileBookmarks
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
