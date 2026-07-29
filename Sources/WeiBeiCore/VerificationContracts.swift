import CoreGraphics
import Foundation

package let verificationProtocolSchemaVersion = 1

package enum VerificationScenarioStatus: String, Codable, Sendable {
    case passed
    case failed
}

package struct VerificationWindowReadyEnvelope: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let processIdentifier: Int32
    package let windowNumber: UInt32
    package let bounds: CGRect
    package let timestamp: Date

    package init(
        schemaVersion: Int = verificationProtocolSchemaVersion,
        processIdentifier: Int32,
        windowNumber: UInt32,
        bounds: CGRect,
        timestamp: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.processIdentifier = processIdentifier
        self.windowNumber = windowNumber
        self.bounds = bounds
        self.timestamp = timestamp
    }

    package func validate() throws {
        guard schemaVersion == verificationProtocolSchemaVersion,
              processIdentifier > 0,
              windowNumber > 0,
              bounds.width >= 1,
              bounds.height >= 1,
              bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite else {
            throw VerificationContractError.invalidEnvelope("window readiness envelope is invalid")
        }
    }
}

package struct VerificationScenarioCompletionEnvelope: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let scenarioID: String
    package let status: VerificationScenarioStatus
    package let evidence: [String]
    package let errorMessage: String?
    package let timestamp: Date

    package init(
        schemaVersion: Int = verificationProtocolSchemaVersion,
        scenarioID: String,
        status: VerificationScenarioStatus,
        evidence: [String],
        errorMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.scenarioID = scenarioID
        self.status = status
        self.evidence = evidence
        self.errorMessage = errorMessage
        self.timestamp = timestamp
    }

    package func validate(expectedScenarioID: String) throws {
        guard schemaVersion == verificationProtocolSchemaVersion,
              scenarioID == expectedScenarioID,
              !scenarioID.isEmpty else {
            throw VerificationContractError.invalidEnvelope("scenario completion envelope is invalid")
        }
        try VerificationContractIO.validateEvidencePaths(evidence)
        if status == .failed,
           errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw VerificationContractError.invalidEnvelope("failed completion requires an error message")
        }
    }
}

package struct LinkedSourcesVerificationReport: Codable, Equatable, Sendable {
    package let importedNotebookID: String
    package let sourceItemIDs: [String]
    package let selectedItemID: String?
    package let linkedSourcesPresented: Bool
    package let showLibrary: Bool
    package let noteRenderMode: String

    package init(
        importedNotebookID: String,
        sourceItemIDs: [String],
        selectedItemID: String?,
        linkedSourcesPresented: Bool,
        showLibrary: Bool,
        noteRenderMode: String
    ) {
        self.importedNotebookID = importedNotebookID
        self.sourceItemIDs = sourceItemIDs
        self.selectedItemID = selectedItemID
        self.linkedSourcesPresented = linkedSourcesPresented
        self.showLibrary = showLibrary
        self.noteRenderMode = noteRenderMode
    }
}

package struct PaneToggleContinuityVerificationReport: Codable, Equatable, Sendable {
    package let passed: Bool
    package let caseCount: Int
    package let notesCyclesPerCase: Int
    package let readerCyclesPerCase: Int
    package let cases: [PaneToggleContinuityCaseReport]

    package init(
        passed: Bool,
        caseCount: Int,
        notesCyclesPerCase: Int,
        readerCyclesPerCase: Int,
        cases: [PaneToggleContinuityCaseReport]
    ) {
        self.passed = passed
        self.caseCount = caseCount
        self.notesCyclesPerCase = notesCyclesPerCase
        self.readerCyclesPerCase = readerCyclesPerCase
        self.cases = cases
    }
}

package struct PaneToggleContinuityCaseReport: Codable, Equatable, Sendable {
    package let name: String
    package let passed: Bool
    package let agentRevisionDelta: UInt64
    package let studyLocationChanged: Bool
    package let htmlLocationCalls: Int
    package let htmlLocationCommits: Int
    package let htmlLocationReasons: [String: Int]
    package let webReaderMakeCount: Int
    package let webReaderDismantleCount: Int
    package let pdfReaderMakeCount: Int
    package let pdfReaderDismantleCount: Int
    package let noteEditorMakeCount: Int
    package let noteEditorDismantleCount: Int
    package let notePreserved: Bool
    package let conversationPreserved: Bool
    package let paneOrderPreserved: Bool

    package init(
        name: String,
        passed: Bool,
        agentRevisionDelta: UInt64,
        studyLocationChanged: Bool,
        htmlLocationCalls: Int,
        htmlLocationCommits: Int,
        htmlLocationReasons: [String: Int],
        webReaderMakeCount: Int,
        webReaderDismantleCount: Int,
        pdfReaderMakeCount: Int,
        pdfReaderDismantleCount: Int,
        noteEditorMakeCount: Int,
        noteEditorDismantleCount: Int,
        notePreserved: Bool,
        conversationPreserved: Bool,
        paneOrderPreserved: Bool
    ) {
        self.name = name
        self.passed = passed
        self.agentRevisionDelta = agentRevisionDelta
        self.studyLocationChanged = studyLocationChanged
        self.htmlLocationCalls = htmlLocationCalls
        self.htmlLocationCommits = htmlLocationCommits
        self.htmlLocationReasons = htmlLocationReasons
        self.webReaderMakeCount = webReaderMakeCount
        self.webReaderDismantleCount = webReaderDismantleCount
        self.pdfReaderMakeCount = pdfReaderMakeCount
        self.pdfReaderDismantleCount = pdfReaderDismantleCount
        self.noteEditorMakeCount = noteEditorMakeCount
        self.noteEditorDismantleCount = noteEditorDismantleCount
        self.notePreserved = notePreserved
        self.conversationPreserved = conversationPreserved
        self.paneOrderPreserved = paneOrderPreserved
    }
}

package struct PaneLayoutStabilityVerificationReport: Codable, Equatable, Sendable {
    package let passed: Bool
    package let transitions: Int
    package let readerVisible: Bool
    package let agentVisible: Bool
    package let notesVisible: Bool
    package let notePreserved: Bool
    package let agentDraftPreserved: Bool
    package let conversationPreserved: Bool
    package let paneOrderPreserved: Bool
    package let agentRevisionDelta: UInt64
    package let studyLocationChanged: Bool
    package let htmlLocationCalls: Int
    package let webReaderMakeCount: Int
    package let webReaderDismantleCount: Int
    package let noteEditorMakeCount: Int
    package let noteEditorDismantleCount: Int

    package init(
        passed: Bool,
        transitions: Int,
        readerVisible: Bool,
        agentVisible: Bool,
        notesVisible: Bool,
        notePreserved: Bool,
        agentDraftPreserved: Bool,
        conversationPreserved: Bool,
        paneOrderPreserved: Bool,
        agentRevisionDelta: UInt64,
        studyLocationChanged: Bool,
        htmlLocationCalls: Int,
        webReaderMakeCount: Int,
        webReaderDismantleCount: Int,
        noteEditorMakeCount: Int,
        noteEditorDismantleCount: Int
    ) {
        self.passed = passed
        self.transitions = transitions
        self.readerVisible = readerVisible
        self.agentVisible = agentVisible
        self.notesVisible = notesVisible
        self.notePreserved = notePreserved
        self.agentDraftPreserved = agentDraftPreserved
        self.conversationPreserved = conversationPreserved
        self.paneOrderPreserved = paneOrderPreserved
        self.agentRevisionDelta = agentRevisionDelta
        self.studyLocationChanged = studyLocationChanged
        self.htmlLocationCalls = htmlLocationCalls
        self.webReaderMakeCount = webReaderMakeCount
        self.webReaderDismantleCount = webReaderDismantleCount
        self.noteEditorMakeCount = noteEditorMakeCount
        self.noteEditorDismantleCount = noteEditorDismantleCount
    }
}

package struct PaneReorderWidthVerificationReport: Codable, Equatable, Sendable {
    package let passed: Bool
    package let baselineOrder: [String]
    package let reorderedOrder: [String]
    package let persistedOrder: [String]
    package let expansionConsumed: Bool
    package let nativeLifecycleStable: Bool
    package let expandedAgentWidth: Double
    package let reorderedAgentWidth: Double
    package let restoredAgentWidth: Double
    package let minimumReadableWidth: Double
    package let widthTolerance: Double
    package let notePreserved: Bool
    package let agentDraftPreserved: Bool
    package let conversationPreserved: Bool
    package let studyLocationChanged: Bool
    package let agentRevisionDelta: UInt64

    package init(
        passed: Bool,
        baselineOrder: [String],
        reorderedOrder: [String],
        persistedOrder: [String],
        expansionConsumed: Bool,
        nativeLifecycleStable: Bool,
        expandedAgentWidth: Double,
        reorderedAgentWidth: Double,
        restoredAgentWidth: Double,
        minimumReadableWidth: Double,
        widthTolerance: Double,
        notePreserved: Bool,
        agentDraftPreserved: Bool,
        conversationPreserved: Bool,
        studyLocationChanged: Bool,
        agentRevisionDelta: UInt64
    ) {
        self.passed = passed
        self.baselineOrder = baselineOrder
        self.reorderedOrder = reorderedOrder
        self.persistedOrder = persistedOrder
        self.expansionConsumed = expansionConsumed
        self.nativeLifecycleStable = nativeLifecycleStable
        self.expandedAgentWidth = expandedAgentWidth
        self.reorderedAgentWidth = reorderedAgentWidth
        self.restoredAgentWidth = restoredAgentWidth
        self.minimumReadableWidth = minimumReadableWidth
        self.widthTolerance = widthTolerance
        self.notePreserved = notePreserved
        self.agentDraftPreserved = agentDraftPreserved
        self.conversationPreserved = conversationPreserved
        self.studyLocationChanged = studyLocationChanged
        self.agentRevisionDelta = agentRevisionDelta
    }
}

package struct PaneContinuityRoleIdentity: Codable, Equatable, Sendable {
    package let hostID: String
    package let parentID: String
    package let contentHostID: String?
    package let contentParentID: String?

    package init(hostID: String, parentID: String, contentHostID: String?, contentParentID: String?) {
        self.hostID = hostID
        self.parentID = parentID
        self.contentHostID = contentHostID
        self.contentParentID = contentParentID
    }
}

package struct PaneContinuitySummary: Codable, Equatable, Sendable {
    package let recorderID: String
    package let samples: Int
    package let transitions: Int
    package let ownershipFailures: Int
    package let blankVisibleFailures: Int
    package let identityFailures: Int
    package let roleIdentities: [String: PaneContinuityRoleIdentity]

    package init(
        recorderID: String,
        samples: Int,
        transitions: Int,
        ownershipFailures: Int,
        blankVisibleFailures: Int,
        identityFailures: Int,
        roleIdentities: [String: PaneContinuityRoleIdentity]
    ) {
        self.recorderID = recorderID
        self.samples = samples
        self.transitions = transitions
        self.ownershipFailures = ownershipFailures
        self.blankVisibleFailures = blankVisibleFailures
        self.identityFailures = identityFailures
        self.roleIdentities = roleIdentities
    }
}

package struct VerificationValidationEnvelope: Codable, Equatable, Sendable {
    package let schemaVersion: Int
    package let scenarioID: String
    package let status: VerificationScenarioStatus
    package let validatedEvidence: [String]
    package let timestamp: Date

    package init(
        schemaVersion: Int = verificationProtocolSchemaVersion,
        scenarioID: String,
        status: VerificationScenarioStatus,
        validatedEvidence: [String],
        timestamp: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.scenarioID = scenarioID
        self.status = status
        self.validatedEvidence = validatedEvidence
        self.timestamp = timestamp
    }
}

package enum VerificationContractError: Error, Equatable, LocalizedError {
    case pathEscapesRoot(String)
    case invalidEvidencePath(String)
    case invalidEnvelope(String)

    package var errorDescription: String? {
        switch self {
        case .pathEscapesRoot(let path):
            return "Verification protocol path escapes its artifact root: \(path)"
        case .invalidEvidencePath(let path):
            return "Verification evidence path is unsafe: \(path)"
        case .invalidEnvelope(let reason):
            return reason
        }
    }
}

package enum VerificationContractIO {
    package static func publish<T: Encodable>(_ value: T, to destination: URL, within root: URL) throws {
        let destination = try validatedURL(destination, within: root)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: destination, options: .atomic)
    }

    package static func decode<T: Decodable>(_ type: T.Type, from source: URL, within root: URL) throws -> T {
        let source = try validatedURL(source, within: root)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: source))
    }

    package static func validatedURL(_ candidate: URL, within root: URL) throws -> URL {
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = normalizedRoot.path.hasSuffix("/") ? normalizedRoot.path : normalizedRoot.path + "/"
        guard normalizedCandidate.path == normalizedRoot.path || normalizedCandidate.path.hasPrefix(prefix) else {
            throw VerificationContractError.pathEscapesRoot(normalizedCandidate.path)
        }
        return normalizedCandidate
    }

    package static func validateEvidencePaths(_ paths: [String]) throws {
        for path in paths {
            let components = NSString(string: path).pathComponents
            guard !path.isEmpty,
                  !path.hasPrefix("/"),
                  !components.contains(".."),
                  path != "." else {
                throw VerificationContractError.invalidEvidencePath(path)
            }
        }
    }
}
