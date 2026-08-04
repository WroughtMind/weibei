import Foundation

public enum CoursePortableItemStorage: Codable, Equatable, Sendable {
    case courseOwned
    case sharedReference(sharedRelativePath: String, expectedContentDigest: String?)

    private enum Kind: String, Codable {
        case courseOwned
        case sharedReference
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case sharedRelativePath
        case expectedContentDigest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .courseOwned:
            self = .courseOwned
        case .sharedReference:
            self = .sharedReference(
                sharedRelativePath: try container.decode(
                    String.self,
                    forKey: .sharedRelativePath
                ),
                expectedContentDigest: try container.decodeIfPresent(
                    String.self,
                    forKey: .expectedContentDigest
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .courseOwned:
            try container.encode(Kind.courseOwned, forKey: .kind)
        case let .sharedReference(sharedRelativePath, expectedContentDigest):
            try container.encode(Kind.sharedReference, forKey: .kind)
            try container.encode(sharedRelativePath, forKey: .sharedRelativePath)
            try container.encodeIfPresent(
                expectedContentDigest,
                forKey: .expectedContentDigest
            )
        }
    }
}

public struct CoursePortableMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var colorIndex: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        title: String,
        colorIndex: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.title = title
        self.colorIndex = colorIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CoursePortableItem: Codable, Equatable, Sendable {
    public var itemID: String
    public var title: String
    public var kind: StudyItemKind
    public var isNotebookNote: Bool
    public var courseRelativePath: String
    public var storage: CoursePortableItemStorage
    public var contentRevision: UInt64
    public var contentDigest: String?
    public var fileByteCount: UInt64?
    public var fileModificationTimeNanoseconds: Int64?
    public var membershipCreatedAt: Date

    public init(
        itemID: String,
        title: String,
        kind: StudyItemKind,
        isNotebookNote: Bool,
        courseRelativePath: String,
        storage: CoursePortableItemStorage,
        contentRevision: UInt64,
        contentDigest: String?,
        fileByteCount: UInt64? = nil,
        fileModificationTimeNanoseconds: Int64? = nil,
        membershipCreatedAt: Date
    ) {
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.isNotebookNote = isNotebookNote
        self.courseRelativePath = courseRelativePath
        self.storage = storage
        self.contentRevision = contentRevision
        self.contentDigest = contentDigest
        self.fileByteCount = fileByteCount
        self.fileModificationTimeNanoseconds =
            fileModificationTimeNanoseconds
        self.membershipCreatedAt = membershipCreatedAt
    }
}

public struct CoursePortableNoteDraft: Codable, Equatable, Sendable {
    public var itemID: String
    public var markdown: String
    public var baselineContentDigest: String?

    public init(
        itemID: String,
        markdown: String,
        baselineContentDigest: String?
    ) {
        self.itemID = itemID
        self.markdown = markdown
        self.baselineContentDigest = baselineContentDigest
    }
}

public enum CourseKnowledgeProfileEntryKind: String, Codable, Equatable, Sendable {
    case overview
    case section
    case concept
    case relation
}

public enum CourseKnowledgeProfileSourceRole: String, Codable, Equatable, Sendable {
    case material
    case note
}

public struct CourseKnowledgeProfileSource: Codable, Equatable, Sendable {
    public var itemID: String
    public var role: CourseKnowledgeProfileSourceRole
    public var location: String?
    public var sourceRevision: String

    public init(
        itemID: String,
        role: CourseKnowledgeProfileSourceRole,
        location: String? = nil,
        sourceRevision: String
    ) {
        self.itemID = itemID
        self.role = role
        self.location = location
        self.sourceRevision = sourceRevision
    }
}

public struct CourseKnowledgeProfileEntry: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: CourseKnowledgeProfileEntryKind
    public var text: String
    public var sources: [CourseKnowledgeProfileSource]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: CourseKnowledgeProfileEntryKind,
        text: String,
        sources: [CourseKnowledgeProfileSource],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sources = sources
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CourseKnowledgeProfile: Codable, Equatable, Sendable {
    public var courseID: UUID
    public var revision: UInt64
    public var overview: String
    public var entries: [CourseKnowledgeProfileEntry]
    public var updatedAt: Date?

    public init(
        courseID: UUID,
        revision: UInt64 = 0,
        overview: String = "",
        entries: [CourseKnowledgeProfileEntry] = [],
        updatedAt: Date? = nil
    ) {
        self.courseID = courseID
        self.revision = revision
        self.overview = overview
        self.entries = entries
        self.updatedAt = updatedAt
    }

    public func retainingAvailableSources(
        materialItemIDs: Set<String>,
        noteItemIDs: Set<String>
    ) -> CourseKnowledgeProfile {
        var retained = self
        retained.entries = entries.filter { entry in
            entry.sources.allSatisfy { source in
                source.role == .note
                    ? noteItemIDs.contains(source.itemID)
                    : materialItemIDs.contains(source.itemID)
            }
        }
        guard retained.entries != entries else { return self }
        retained.overview = retained.entries
            .filter { $0.kind == .overview }
            .max(by: { $0.updatedAt < $1.updatedAt })?.text ?? ""
        retained.revision &+= 1
        retained.updatedAt = retained.entries.map(\.updatedAt).max()
        return retained
    }
}

public enum CoursePortableStateError: LocalizedError, Equatable {
    case unsupportedSchema
    case courseIdentityMismatch
    case invalidMetadata
    case missingCourseItem
    case invalidItemStorage
    case duplicateItemID
    case duplicateItemPath
    case unsafeRelativePath
    case invalidChatScope
    case duplicateChatID
    case crossCourseReference
    case invalidLearningMemoryScope
    case invalidCourseKnowledgeProfile
    case invalidRelation
    case invalidStudyLocation
    case invalidResumePoint
    case invalidNoteDraft
    case stateConflict
    case writeVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            return "课程状态版本不受支持。"
        case .courseIdentityMismatch:
            return "课程状态与课程身份不一致。"
        case .invalidMetadata:
            return "课程状态中的课程信息无效。"
        case .missingCourseItem:
            return "课程成员缺少可携带的资料记录。"
        case .invalidItemStorage:
            return "课程资料的存储归属与课程不一致。"
        case .duplicateItemID:
            return "课程状态包含重复的资料 ID。"
        case .duplicateItemPath:
            return "课程状态包含重复的资料路径。"
        case .unsafeRelativePath:
            return "课程状态包含不安全的相对路径。"
        case .invalidChatScope:
            return "课程状态包含不属于本课程的对话。"
        case .duplicateChatID:
            return "课程状态包含重复的对话 ID。"
        case .crossCourseReference:
            return "课程状态包含跨课程引用。"
        case .invalidLearningMemoryScope:
            return "课程学习记忆的作用域不正确。"
        case .invalidCourseKnowledgeProfile:
            return "课程知识档案包含无效或越界的内容。"
        case .invalidRelation:
            return "课程状态包含无效的文稿与笔记关系。"
        case .invalidStudyLocation:
            return "课程状态包含无效的阅读位置。"
        case .invalidResumePoint:
            return "课程状态包含无效的继续学习位置。"
        case .invalidNoteDraft:
            return "课程状态包含无效的笔记草稿。"
        case .stateConflict:
            return "课程文件夹与本机缓存中的课程状态发生冲突，已保留两边内容并停止覆盖。"
        case .writeVerificationFailed:
            return "课程状态写入后无法通过完整性校验，已停止提交。"
        }
    }
}

public struct CoursePortableState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var courseID: UUID
    public var schemaVersion: Int
    public var revision: UInt64
    public var savedAt: Date
    public var metadata: CoursePortableMetadata
    public var items: [CoursePortableItem]
    public var studySessions: [StudySession]
    public var learningMemoryState: ScopedLearningMemoryState?
    public var courseKnowledgeProfile: CourseKnowledgeProfile?
    public var noteSourceLinks: [NoteSourceLink]
    public var studyLocationsByItemID: [String: StudyLocation]
    public var resumePoint: CourseResumePoint?
    public var pendingNoteDrafts: [CoursePortableNoteDraft]

    public init(
        courseID: UUID,
        schemaVersion: Int = currentSchemaVersion,
        revision: UInt64,
        savedAt: Date,
        metadata: CoursePortableMetadata,
        items: [CoursePortableItem],
        studySessions: [StudySession],
        learningMemoryState: ScopedLearningMemoryState?,
        courseKnowledgeProfile: CourseKnowledgeProfile? = nil,
        noteSourceLinks: [NoteSourceLink],
        studyLocationsByItemID: [String: StudyLocation],
        resumePoint: CourseResumePoint?,
        pendingNoteDrafts: [CoursePortableNoteDraft]
    ) {
        self.courseID = courseID
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.savedAt = savedAt
        self.metadata = metadata
        self.items = items
        self.studySessions = studySessions
        self.learningMemoryState = learningMemoryState
        self.courseKnowledgeProfile = courseKnowledgeProfile
        self.noteSourceLinks = noteSourceLinks
        self.studyLocationsByItemID = studyLocationsByItemID
        self.resumePoint = resumePoint
        self.pendingNoteDrafts = pendingNoteDrafts
    }

    public func validated(expectedCourseID: UUID) throws -> CoursePortableState {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoursePortableStateError.unsupportedSchema
        }
        guard courseID == expectedCourseID else {
            throw CoursePortableStateError.courseIdentityMismatch
        }
        guard !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoursePortableStateError.invalidMetadata
        }

        var itemIDs = Set<String>()
        var itemPaths = Set<String>()
        var noteItemIDs = Set<String>()
        var materialItemIDs = Set<String>()
        for item in items {
            guard !item.itemID.isEmpty,
                  itemIDs.insert(item.itemID).inserted else {
                throw CoursePortableStateError.duplicateItemID
            }
            guard Self.isSafeRelativePath(item.courseRelativePath) else {
                throw CoursePortableStateError.unsafeRelativePath
            }
            guard itemPaths.insert(item.courseRelativePath).inserted else {
                throw CoursePortableStateError.duplicateItemPath
            }
            guard Self.hasValidRoleAndKind(item) else {
                throw CoursePortableStateError.invalidItemStorage
            }
            switch item.storage {
            case .courseOwned:
                break
            case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ):
                guard !item.isNotebookNote,
                      Self.isStrictSharedMaterialPath(sharedRelativePath),
                      let expectedContentDigest,
                      Self.isSHA256(expectedContentDigest),
                      item.contentDigest == expectedContentDigest else {
                    throw CoursePortableStateError.invalidItemStorage
                }
            }
            if item.isNotebookNote {
                noteItemIDs.insert(item.itemID)
            } else {
                materialItemIDs.insert(item.itemID)
            }
        }

        var relationIDs = Set<UUID>()
        var relationsByID: [UUID: NoteSourceLink] = [:]
        for relation in noteSourceLinks {
            guard relationIDs.insert(relation.id).inserted,
                  noteItemIDs.contains(relation.noteItemID),
                  materialItemIDs.contains(relation.sourceItemID) else {
                throw CoursePortableStateError.invalidRelation
            }
            relationsByID[relation.id] = relation
        }

        var chatIDs = Set<UUID>()
        var messageIDsByChatID: [UUID: Set<UUID>] = [:]
        let memoryIDs = Set(learningMemoryState?.entries.map(\.id) ?? [])
        if let courseKnowledgeProfile {
            let entryIDs = Set(courseKnowledgeProfile.entries.map(\.id))
            guard courseKnowledgeProfile.courseID == courseID,
                  courseKnowledgeProfile.overview.count <= 2_000,
                  courseKnowledgeProfile.entries.count <= 200,
                  entryIDs.count == courseKnowledgeProfile.entries.count,
                  courseKnowledgeProfile.entries.allSatisfy({ entry in
                      !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && entry.text.count <= 1_200
                          && !entry.sources.isEmpty
                          && entry.sources.count <= 8
                          && entry.sources.allSatisfy { source in
                              itemIDs.contains(source.itemID)
                                  && source.sourceRevision.count <= 500
                                  && !source.sourceRevision.isEmpty
                                  && (source.location?.count ?? 0) <= 500
                                  && (source.role == .note
                                      ? noteItemIDs.contains(source.itemID)
                                      : materialItemIDs.contains(source.itemID))
                          }
                  }) else {
                throw CoursePortableStateError.invalidCourseKnowledgeProfile
            }
        }
        for session in studySessions {
            guard session.courseID == courseID,
                  session.scopeNeedsReview == false,
                  session.focusItemIDs.allSatisfy(itemIDs.contains),
                  session.materialItemID.map(materialItemIDs.contains) ?? true else {
                throw CoursePortableStateError.invalidChatScope
            }
            guard chatIDs.insert(session.id).inserted else {
                throw CoursePortableStateError.duplicateChatID
            }
            let chatMessageIDs = Set(session.messages.map(\.id))
            guard chatMessageIDs.count == session.messages.count else {
                throw CoursePortableStateError.invalidChatScope
            }
            messageIDsByChatID[session.id] = chatMessageIDs
            for message in session.messages {
                guard message.toolTrace.isEmpty else {
                    throw CoursePortableStateError.crossCourseReference
                }
                for source in message.sources {
                    guard source.courseID.map({ $0 == courseID }) ?? true,
                          source.itemID.map(itemIDs.contains) ?? true else {
                        throw CoursePortableStateError.crossCourseReference
                    }
                    if let sourceItemID = source.itemID {
                        switch source.kind {
                        case .material:
                            guard materialItemIDs.contains(sourceItemID) else {
                                throw CoursePortableStateError.crossCourseReference
                            }
                        case .note:
                            guard noteItemIDs.contains(sourceItemID) else {
                                throw CoursePortableStateError.crossCourseReference
                            }
                        case .selection:
                            break
                        }
                    }
                }
                for action in message.actions {
                    guard action.targetItemID.map(itemIDs.contains) ?? true,
                          action.sourceItemID.map(itemIDs.contains) ?? true else {
                        throw CoursePortableStateError.crossCourseReference
                    }
                    switch action.kind {
                    case .writeNote:
                        guard action.targetItemID.map(noteItemIDs.contains) ?? true else {
                            throw CoursePortableStateError.crossCourseReference
                        }
                    case .createRelation:
                        guard action.targetItemID.map(noteItemIDs.contains) ?? true,
                              action.sourceItemID.map(materialItemIDs.contains) ?? true else {
                            throw CoursePortableStateError.crossCourseReference
                        }
                    }
                    if let relationID = action.createdRelationID {
                        guard action.kind == .createRelation,
                              let targetItemID = action.targetItemID,
                              let sourceItemID = action.sourceItemID,
                              let relation = relationsByID[relationID],
                              relation.noteItemID == targetItemID,
                              relation.sourceItemID == sourceItemID else {
                            throw CoursePortableStateError.invalidRelation
                        }
                    }
                }
                if let memoryUpdate = message.memoryUpdate {
                    guard memoryUpdate.memoryIDs.allSatisfy(memoryIDs.contains) else {
                        throw CoursePortableStateError.crossCourseReference
                    }
                }
                if let origin = message.origin {
                    guard origin.courseID == courseID,
                          origin.chatID == session.id else {
                        throw CoursePortableStateError.crossCourseReference
                    }
                }
            }
        }

        if let learningMemoryState {
            guard learningMemoryState.scope == .course(courseID),
                  Set(learningMemoryState.entries.map(\.id)).count
                    == learningMemoryState.entries.count else {
                throw CoursePortableStateError.invalidLearningMemoryScope
            }
            func hasValidChatReference(
                sessionID: UUID?,
                messageID: UUID?
            ) -> Bool {
                guard let sessionID else {
                    return messageID == nil
                }
                guard let chatMessageIDs =
                        messageIDsByChatID[sessionID] else {
                    return false
                }
                return messageID.map(chatMessageIDs.contains) ?? true
            }
            for entry in learningMemoryState.entries {
                guard hasValidChatReference(
                    sessionID: entry.sessionID,
                    messageID: entry.messageID
                ),
                (entry.revisions ?? []).allSatisfy({
                    hasValidChatReference(
                        sessionID: $0.sessionID,
                        messageID: $0.messageID
                    )
                }) else {
                    throw CoursePortableStateError
                        .invalidLearningMemoryScope
                }
            }
        }

        for (itemID, location) in studyLocationsByItemID {
            guard materialItemIDs.contains(itemID),
                  location.itemID == itemID else {
                throw CoursePortableStateError.invalidStudyLocation
            }
        }

        if let resumePoint {
            guard resumePoint.courseID == courseID,
                  resumePoint.materialLocation.map({
                    materialItemIDs.contains($0.itemID)
                }) ?? true,
                  resumePoint.chatID.map(chatIDs.contains) ?? true,
                  resumePoint.noteItemID.map(noteItemIDs.contains) ?? true else {
                throw CoursePortableStateError.invalidResumePoint
            }
        }

        var draftItemIDs = Set<String>()
        for draft in pendingNoteDrafts {
            guard noteItemIDs.contains(draft.itemID),
                  draftItemIDs.insert(draft.itemID).inserted else {
                throw CoursePortableStateError.invalidNoteDraft
            }
        }
        return self
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !components.isEmpty
            && components.allSatisfy { component in
                guard !component.isEmpty,
                      component != ".",
                      component != ".." else {
                    return false
                }
                let normalized = String(component)
                    .precomposedStringWithCanonicalMapping
                    .lowercased()
                return !normalized.hasPrefix(".")
            }
    }

    private static func hasValidRoleAndKind(
        _ item: CoursePortableItem
    ) -> Bool {
        let components = item.courseRelativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.count >= 2,
              let first = components.first,
              let fileName = components.last,
              !fileName.isEmpty,
              !fileName.hasPrefix(".") else {
            return false
        }
        let pathExtension = (String(fileName) as NSString)
            .pathExtension
            .lowercased()
        guard kind(forPathExtension: pathExtension) == item.kind else {
            return false
        }
        let pathDefinesNotebookNote =
            first == "笔记" && item.kind == .markdown
        if item.isNotebookNote {
            guard pathDefinesNotebookNote,
                  case .courseOwned = item.storage else {
                return false
            }
            return true
        }
        return !pathDefinesNotebookNote
    }

    private static func isStrictSharedMaterialPath(_ path: String) -> Bool {
        guard isSafeRelativePath(path) else { return false }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              components[0] == "共享文稿",
              !components[1].hasPrefix(".") else {
            return false
        }
        return kind(
            forPathExtension: (String(components[1]) as NSString)
                .pathExtension
                .lowercased()
        ) != nil
    }

    private static func kind(
        forPathExtension pathExtension: String
    ) -> StudyItemKind? {
        switch pathExtension {
        case "pdf":
            return .pdf
        case "html", "htm":
            return .html
        case "md", "markdown":
            return .markdown
        case "txt", "text":
            return .text
        case "png", "jpg", "jpeg", "webp", "gif", "heic", "tif",
             "tiff", "bmp":
            return .text
        default:
            return nil
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                ("0"..."9").contains(Character(String($0)))
                    || ("a"..."f").contains(Character(String($0)))
            }
    }
}
