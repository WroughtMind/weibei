import Foundation
import WeiBeiCore

struct CourseProjectResolvedBookmark {
    var url: URL
    var isStale: Bool
}

enum CourseProjectMutationStage: String, CaseIterable {
    case afterStagingDirectory
    case beforeManifestWrite
    case beforeAtomicPlacement
    case beforeOwnedRollbackCleanup
}

struct CourseProjectManifest: Codable, Equatable {
    static let currentSchemaVersion = 1

    var courseID: UUID
    var schemaVersion: Int

    init(courseID: UUID, schemaVersion: Int = currentSchemaVersion) {
        self.courseID = courseID
        self.schemaVersion = schemaVersion
    }

    static func read(from url: URL) throws -> CourseProjectManifest {
        try JSONDecoder().decode(CourseProjectManifest.self, from: Data(contentsOf: url))
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

enum CourseProjectRootError: LocalizedError {
    case emptyTitle
    case invalidDirectoryName
    case nonFileURL
    case missingLibrary
    case unavailableLibrary
    case rootMustNotExist
    case rootMustExist
    case rootMustBeDirectory
    case rootOutsideLibrary
    case dangerousRoot
    case overlappingRoot
    case rootAlreadyRegistered
    case rootIdentityUnavailable
    case bookmarkUnavailable
    case bookmarkResolutionFailed
    case securityScopeDenied
    case libraryIdentityMismatch
    case metadataConflict
    case manifestMismatch
    case workspaceSaveFailed

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "课程名称不能为空。"
        case .invalidDirectoryName:
            return "这个课程名称无法生成安全的文件夹名，请换一个名称。"
        case .nonFileURL:
            return "课程根目录必须是本地文件夹。"
        case .missingLibrary:
            return "请先配置课程资料库。"
        case .unavailableLibrary:
            return "课程资料库当前不可访问。"
        case .rootMustNotExist:
            return "新建课程的位置已经存在，请改用“纳入现有课程文件夹”。"
        case .rootMustExist:
            return "要接管的课程文件夹不存在。"
        case .rootMustBeDirectory:
            return "课程根必须是文件夹。"
        case .rootOutsideLibrary:
            return "新建课程必须位于已配置的课程资料库内。"
        case .dangerousRoot:
            return "不能把系统根、主目录、文稿目录、资料库根或魏碑共享状态目录作为课程根。"
        case .overlappingRoot:
            return "课程根不能与已有课程互相包含。"
        case .rootAlreadyRegistered:
            return "这个课程文件夹已经被魏碑纳入。"
        case .rootIdentityUnavailable:
            return "无法确认课程根的本地文件身份。"
        case .bookmarkUnavailable:
            return "无法保存文件夹访问授权。"
        case .bookmarkResolutionFailed:
            return "无法恢复文件夹访问授权。"
        case .securityScopeDenied:
            return "系统没有授予文件夹访问权限。"
        case .libraryIdentityMismatch:
            return "所选文件夹不是原来的课程资料库；更换资料库需要单独迁移，不能静默改绑。"
        case .metadataConflict:
            return "这个文件夹已有未知或损坏的 .weibei 元数据，魏碑不会覆盖它。"
        case .manifestMismatch:
            return "课程 manifest 与当前课程记录冲突。"
        case .workspaceSaveFailed:
            return "课程状态没有成功保存。魏碑只撤销能确认属于本次操作的内容；如果磁盘内容已经变化，会原样保留。"
        }
    }
}

enum CourseProjectPathPolicy {
    static func existingDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw CourseProjectRootError.nonFileURL }
        let aliasResolved = try resolveAliasIfNeeded(url.standardizedFileURL)
        let canonical = aliasResolved.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory) else {
            throw CourseProjectRootError.rootMustExist
        }
        guard isDirectory.boolValue else {
            throw CourseProjectRootError.rootMustBeDirectory
        }
        return canonical
    }

    static func newDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw CourseProjectRootError.nonFileURL }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CourseProjectRootError.rootMustNotExist
        }
        let rawParent = url.standardizedFileURL.deletingLastPathComponent()
        let parent = try existingDirectory(rawParent)
        let component = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !component.isEmpty, component != ".", component != ".." else {
            throw CourseProjectRootError.dangerousRoot
        }
        return parent.appendingPathComponent(component, isDirectory: true).standardizedFileURL
    }

    static func isSame(_ lhs: URL, _ rhs: URL) -> Bool {
        foldedComponents(lhs) == foldedComponents(rhs)
    }

    static func contains(_ root: URL, _ candidate: URL, includingRoot: Bool = true) -> Bool {
        let rootComponents = foldedComponents(root)
        let candidateComponents = foldedComponents(candidate)
        guard candidateComponents.count >= rootComponents.count else { return false }
        if !includingRoot, candidateComponents.count == rootComponents.count { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    static func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
        contains(lhs, rhs) || contains(rhs, lhs)
    }

    static func relativePath(of child: URL, inside root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              foldedComponents(child).prefix(rootComponents.count).elementsEqual(foldedComponents(root)) else {
            return nil
        }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    static func resolvedRelativePath(_ relativePath: String, inside root: URL) -> URL? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        let candidate = components.reduce(root) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(root, resolved, includingRoot: false) else { return nil }
        return resolved
    }

    private static func resolveAliasIfNeeded(_ url: URL) throws -> URL {
        let values = try? url.resourceValues(forKeys: [.isAliasFileKey])
        guard values?.isAliasFile == true else { return url }
        return try URL(resolvingAliasFileAt: url, options: [.withoutUI])
    }

    private static func foldedComponents(_ url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.map {
            $0.precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}
