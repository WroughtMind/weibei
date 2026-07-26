import Darwin
import CryptoKit
import Foundation
import Security

public struct PiAgentResources: Sendable {
    public static let requiredSkillNames = [
        "weibei-study-companion",
        "weibei-course-wayfinding",
        "weibei-close-reading",
        "weibei-note-making",
        "weibei-recall-practice",
    ]
    public static let requiredRichAnswerSkillNames = [
        "rich-answer-director",
        "professional-visualization",
        "deep-interaction-components",
        "generative-composition",
    ]
    public static var allRequiredSkillNames: [String] {
        requiredSkillNames + requiredRichAnswerSkillNames
    }

    public var rootURL: URL
    public var extensionURL: URL
    public var pythonArtifactWorkerURL: URL
    public var skillsURL: URL
    public var systemPrompt: String

    public static func bundled() throws -> PiAgentResources {
        let bundleName = "WeiBei_WeiBeiCore.bundle"
        let packagedBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent(bundleName) }
            .flatMap(Bundle.init(url:))
        let legacyBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent(bundleName))
        let resourceBundle = packagedBundle ?? legacyBundle ?? Bundle.module
        guard let rootURL = resourceBundle.url(forResource: "AgentResources", withExtension: nil) else {
            throw PiAgentRuntimeError.resourcesMissing("AgentResources")
        }
        let extensionURL = rootURL.appendingPathComponent("extension.ts")
        let pythonArtifactWorkerURL = rootURL
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent("rich_answer_worker.py")
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        let hasRequiredSkills = requiredSkillNames.allSatisfy { skillName in
            FileManager.default.fileExists(
                atPath: skillsURL.appendingPathComponent(skillName).appendingPathComponent("SKILL.md").path
            )
        }
        let hasRequiredRichAnswerSkills = requiredRichAnswerSkillNames.allSatisfy { skillName in
            FileManager.default.fileExists(
                atPath: skillsURL
                    .appendingPathComponent("rich-answer", isDirectory: true)
                    .appendingPathComponent(skillName, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                    .path
            )
        }
        guard FileManager.default.fileExists(atPath: extensionURL.path),
              FileManager.default.fileExists(atPath: pythonArtifactWorkerURL.path),
              hasRequiredSkills,
              hasRequiredRichAnswerSkills,
              let systemPrompt = try? String(contentsOf: systemURL, encoding: .utf8),
              !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PiAgentRuntimeError.resourcesMissing(rootURL.path)
        }
        return PiAgentResources(
            rootURL: rootURL,
            extensionURL: extensionURL,
            pythonArtifactWorkerURL: pythonArtifactWorkerURL,
            skillsURL: skillsURL,
            systemPrompt: systemPrompt
        )
    }
}

public struct PiRuntimeManifest: Decodable, Equatable, Sendable {
    public var schemaVersion: Int
    public var piVersion: String
    public var sourceRepository: String
    public var sourceCommit: String
    public var license: String
}

public enum PiBundledRuntime {
    public static let requiredVersion = "0.80.2"

    private struct PackageMetadata: Decodable {
        var version: String
    }

    public static func validate(
        executableURL: URL,
        fileManager: FileManager = .default,
        containingAppURL: URL? = nil
    ) throws -> PiRuntimeManifest {
        let executableURL = executableURL.standardizedFileURL
        let binURL = executableURL.deletingLastPathComponent()
        let runtimeURL = binURL.deletingLastPathComponent()
        let manifestURL = runtimeURL.appendingPathComponent("manifest.json")
        let integrityURL = runtimeURL.appendingPathComponent("binary.sha256")
        let packageURL = binURL.appendingPathComponent("package.json")
        let requiredFiles = [
            executableURL,
            packageURL,
            binURL.appendingPathComponent("theme/dark.json"),
            binURL.appendingPathComponent("theme/light.json"),
            runtimeURL.appendingPathComponent("LICENSE"),
            runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"),
            manifestURL,
            integrityURL,
        ]
        guard fileManager.isExecutableFile(atPath: executableURL.path),
              requiredFiles.dropFirst().allSatisfy({ fileManager.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PiRuntimeManifest.self, from: data),
              let packageData = try? Data(contentsOf: packageURL),
              let package = try? JSONDecoder().decode(PackageMetadata.self, from: packageData),
              let expectedHash = try? String(contentsOf: integrityURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              manifest.schemaVersion == 1,
              manifest.piVersion == requiredVersion,
              package.version == requiredVersion,
              manifest.license == "MIT",
              !manifest.sourceRepository.isEmpty,
              manifest.sourceCommit.count == 40,
              expectedHash.count == 64,
              expectedHash.allSatisfy({ $0.isHexDigit }),
              (try? sha256(of: executableURL)) == expectedHash,
              hasExpectedArchitecture(executableURL),
              hasValidCodeSignature(executableURL) else {
            throw PiAgentRuntimeError.resourcesMissing(runtimeURL.path)
        }

        let defaultAppURL = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil
        if let appURL = (containingAppURL ?? defaultAppURL)?.standardizedFileURL,
           executableURL.path.hasPrefix(appURL.path + "/"),
           !hasValidCodeSignature(appURL) {
            throw PiAgentRuntimeError.resourcesMissing(appURL.path)
        }
        return manifest
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hasExpectedArchitecture(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 8) else { return false }
        try? handle.close()
        let bytes = Array(data)
        guard bytes.count == 8, Array(bytes[0..<4]) == [0xcf, 0xfa, 0xed, 0xfe] else { return false }
        #if arch(arm64)
        return Array(bytes[4..<8]) == [0x0c, 0x00, 0x00, 0x01]
        #elseif arch(x86_64)
        return Array(bytes[4..<8]) == [0x07, 0x00, 0x00, 0x01]
        #else
        return false
        #endif
    }

    private static func hasValidCodeSignature(_ url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate))
        return SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess
    }
}

public enum PiExecutableLocator {
    public static func locate(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        validator: (URL, FileManager) -> Bool = { candidate, fileManager in
            (try? PiBundledRuntime.validate(executableURL: candidate, fileManager: fileManager)) != nil
        }
    ) -> URL? {
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Resources/PiRuntime/bin/pi"),
            bundleURL.appendingPathComponent("PiRuntime/bin/pi"),
        ]
        return candidates.first { candidate in
            fileManager.isExecutableFile(atPath: candidate.path) && validator(candidate, fileManager)
        }
    }
}
