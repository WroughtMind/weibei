import Foundation

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
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        courseID: UUID,
        itemID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.courseID = courseID
        self.itemID = itemID
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
        var oldestByPair: [String: CourseItemMembership] = [:]
        for value in values {
            let key = "\(value.courseID.uuidString)|\(value.itemID)"
            if let existing = oldestByPair[key], existing.createdAt <= value.createdAt {
                continue
            }
            oldestByPair[key] = value
        }
        return oldestByPair.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
