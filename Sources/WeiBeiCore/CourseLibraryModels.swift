import Foundation

public enum CourseLibraryLayout {
    public static let defaultFolderName = "魏碑资料库"
    public static let commonMaterialsDirectoryName = "通用资料"
    public static let commonNotesDirectoryName = "通用笔记"
    public static let courseMaterialsDirectoryName = "文稿"
    public static let courseNotesDirectoryName = "笔记"

    public static func defaultRootURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(defaultFolderName, isDirectory: true)
    }
}

public struct Course: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var colorIndex: Int
    public var sourceRootPath: String?
    public var sourceRootRelativePath: String?
    public var sourceRootIdentity: ImportedFileIdentity?
    public var sourceRootBookmarkData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        colorIndex: Int = 0,
        sourceRootPath: String? = nil,
        sourceRootRelativePath: String? = nil,
        sourceRootIdentity: ImportedFileIdentity? = nil,
        sourceRootBookmarkData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.colorIndex = colorIndex
        self.sourceRootPath = sourceRootPath
        self.sourceRootRelativePath = sourceRootRelativePath
        self.sourceRootIdentity = sourceRootIdentity
        self.sourceRootBookmarkData = sourceRootBookmarkData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CourseItemMembership: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var courseID: UUID
    public var itemID: String
    /// Entry path relative to this course root. Shared documents can have a different entry in each course.
    public var courseRelativePath: String?
    /// Identity of the course entry itself (including a future shared-document link), not the document identity.
    public var entryIdentity: ImportedFileIdentity?
    /// Volume-scoped filesystem document identifier when supported, independent of file identity.
    public var documentIdentifier: UInt64?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        courseID: UUID,
        itemID: String,
        courseRelativePath: String? = nil,
        entryIdentity: ImportedFileIdentity? = nil,
        documentIdentifier: UInt64? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.courseID = courseID
        self.itemID = itemID
        self.courseRelativePath = courseRelativePath
        self.entryIdentity = entryIdentity
        self.documentIdentifier = documentIdentifier
        self.createdAt = createdAt
    }
}

public struct CourseItemMemberships: Sendable {
    public private(set) var values: [CourseItemMembership]

    public init(values: [CourseItemMembership] = []) {
        self.values = Self.normalized(values)
    }

    public func courseIDs(for itemID: String) -> [UUID] {
        values
            .lazy
            .filter { $0.itemID == itemID }
            .map(\.courseID)
    }

    public func itemIDs(in courseID: UUID) -> [String] {
        values
            .lazy
            .filter { $0.courseID == courseID }
            .map(\.itemID)
    }

    public mutating func assign(itemIDs: Set<String>, to courseID: UUID) {
        let existingItemIDs = Set(values.lazy.filter { $0.courseID == courseID }.map(\.itemID))
        for itemID in itemIDs.subtracting(existingItemIDs).sorted() {
            values.append(CourseItemMembership(courseID: courseID, itemID: itemID))
        }
        values = Self.normalized(values)
    }

    public mutating func replaceCourses(for itemID: String, courseIDs: Set<UUID>) {
        let retained = values.filter { $0.itemID != itemID || courseIDs.contains($0.courseID) }
        let existingCourseIDs = Set(retained.lazy.filter { $0.itemID == itemID }.map(\.courseID))
        let additions = courseIDs.subtracting(existingCourseIDs).sorted { $0.uuidString < $1.uuidString }.map {
            CourseItemMembership(courseID: $0, itemID: itemID)
        }
        values = Self.normalized(retained + additions)
    }

    public mutating func removeCourse(_ courseID: UUID) {
        values.removeAll { $0.courseID == courseID }
    }

    public mutating func removeItem(_ itemID: String) {
        values.removeAll { $0.itemID == itemID }
    }

    @discardableResult
    public mutating func sanitize(validCourseIDs: Set<UUID>, validItemIDs: Set<String>) -> Bool {
        let next = Self.normalized(values.filter {
            validCourseIDs.contains($0.courseID) && validItemIDs.contains($0.itemID)
        })
        guard next != values else { return false }
        values = next
        return true
    }

    private static func normalized(_ values: [CourseItemMembership]) -> [CourseItemMembership] {
        var valuesByPair: [String: [CourseItemMembership]] = [:]
        for value in values {
            let key = "\(value.courseID.uuidString)|\(value.itemID)"
            valuesByPair[key, default: []].append(value)
        }
        return valuesByPair.values.flatMap { group -> [CourseItemMembership] in
            let sorted = group.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard Set(sorted.compactMap(\.courseRelativePath)).count <= 1,
                  Set(sorted.compactMap(\.entryIdentity)).count <= 1,
                  Set(sorted.compactMap(\.documentIdentifier)).count <= 1,
                  var merged = sorted.first else {
                return sorted
            }
            merged.courseRelativePath = sorted.compactMap(\.courseRelativePath).first
            merged.entryIdentity = sorted.compactMap(\.entryIdentity).first
            merged.documentIdentifier = sorted.compactMap(\.documentIdentifier).first
            return [merged]
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
