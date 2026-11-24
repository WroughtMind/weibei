import Combine
import Foundation

enum NoteSaveStatus: Equatable {
    case idle
    case saving
    case writtenToFile
    case savedInWeiBei
    case failed
    case externallyModified

    /// 后台保存保持安静，标题栏只显示已发生的失败或冲突。
    var showsStatusLabel: Bool {
        self == .failed || self == .externallyModified
    }
}

enum NoteEditingSessionError: Error, Equatable {
    case bridgeUnavailable
    case documentChanged
    case snapshotTimedOut
}

@MainActor
final class NoteEditingSession: ObservableObject {
    typealias SnapshotCompletion = (
        Result<NoteEditorSnapshotReadyEvent, NoteEditingSessionError>
    ) -> Void

    private struct PendingSnapshot {
        let requestID: String
        var minimumRevision: UInt64
        var persists: Bool
        var completions: [SnapshotCompletion]
    }

    private var onSnapshotRequest: ((NoteEditorSnapshotRequest) -> Void)?
    private var readCompactTypography: (() async -> Bool?)?
    private var snapshotRequestHandlerToken: UUID?
    private let onSnapshotAccepted: (NoteEditorSnapshotReadyEvent) -> Void
    private var pendingSnapshot: PendingSnapshot?
    private var idleSnapshotTask: Task<Void, Never>?
    private var maximumAgeSnapshotTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?
    private let idleSnapshotDelay: Duration
    private let maximumSnapshotAge: Duration
    private let snapshotTimeout: Duration

    private(set) var documentID: String
    private(set) var documentGeneration: UInt64
    private(set) var currentRevision: UInt64
    private(set) var savedRevision: UInt64
    private(set) var dirty = false
    @Published private(set) var saveStatus: NoteSaveStatus = .idle

    init(
        documentID: String,
        initialRevision: UInt64 = 0,
        idleSnapshotDelay: Duration = .milliseconds(850),
        maximumSnapshotAge: Duration = .seconds(5),
        snapshotTimeout: Duration = .seconds(5),
        onSnapshotRequest: ((NoteEditorSnapshotRequest) -> Void)? = nil,
        onSnapshotAccepted: @escaping (NoteEditorSnapshotReadyEvent) -> Void = { _ in }
    ) {
        self.documentID = documentID
        documentGeneration = 1
        currentRevision = initialRevision
        savedRevision = initialRevision
        self.idleSnapshotDelay = idleSnapshotDelay
        self.maximumSnapshotAge = maximumSnapshotAge
        self.snapshotTimeout = snapshotTimeout
        self.onSnapshotRequest = onSnapshotRequest
        snapshotRequestHandlerToken = onSnapshotRequest == nil ? nil : UUID()
        self.onSnapshotAccepted = onSnapshotAccepted
    }

    @discardableResult
    func bindSnapshotRequestHandler(
        compactTypography: (() async -> Bool?)? = nil,
        _ handler: @escaping (NoteEditorSnapshotRequest) -> Void
    ) -> UUID {
        failPendingSnapshot(with: .bridgeUnavailable)
        let token = UUID()
        snapshotRequestHandlerToken = token
        onSnapshotRequest = handler
        readCompactTypography = compactTypography
        return token
    }

    func unbindSnapshotRequestHandler(_ token: UUID) {
        guard snapshotRequestHandlerToken == token else { return }
        snapshotRequestHandlerToken = nil
        onSnapshotRequest = nil
        readCompactTypography = nil
        failPendingSnapshot(with: .bridgeUnavailable)
        cancelScheduledSnapshots()
    }

    func compactTypographyForExport(documentID: String) async -> Bool? {
        guard self.documentID == documentID else { return nil }
        let generation = documentGeneration
        let binding = snapshotRequestHandlerToken
        let compact = await readCompactTypography?()
        return generation == documentGeneration && binding == snapshotRequestHandlerToken ? compact : nil
    }

    @discardableResult
    func replaceDocument(
        with documentID: String,
        initialRevision: UInt64 = 0
    ) -> UInt64 {
        failPendingSnapshot(with: .documentChanged)
        cancelScheduledSnapshots()

        self.documentID = documentID
        documentGeneration &+= 1
        currentRevision = initialRevision
        savedRevision = initialRevision
        dirty = false
        adoptSaveStatus(.idle)
        return documentGeneration
    }

    @discardableResult
    func invalidateBridgeGeneration() -> UInt64 {
        failPendingSnapshot(with: .bridgeUnavailable)
        cancelScheduledSnapshots()
        documentGeneration &+= 1
        return documentGeneration
    }

    @discardableResult
    func receive(_ event: NoteEditorDirtyChangedEvent) -> Bool {
        guard matchesCurrentDocument(
            protocolVersion: event.protocolVersion,
            documentID: event.documentID,
            documentGeneration: event.documentGeneration
        ), event.revision >= currentRevision else {
            return false
        }

        currentRevision = event.revision
        dirty = event.dirty || currentRevision != savedRevision
        if dirty {
            if saveStatus != .externallyModified {
                adoptSaveStatus(.saving)
            }
            scheduleSnapshot()
        }
        return true
    }

    @discardableResult
    func requestSnapshot(
        minimumRevision: UInt64? = nil,
        persists: Bool = true,
        completion: SnapshotCompletion? = nil
    ) -> Bool {
        guard onSnapshotRequest != nil else {
            completion?(.failure(.bridgeUnavailable))
            return false
        }

        let requiredRevision = max(minimumRevision ?? currentRevision, currentRevision)
        var pending = pendingSnapshot ?? PendingSnapshot(
            requestID: UUID().uuidString,
            minimumRevision: requiredRevision,
            persists: persists,
            completions: []
        )
        pending.minimumRevision = max(pending.minimumRevision, requiredRevision)
        pending.persists = pending.persists || persists
        if let completion {
            pending.completions.append(completion)
        }
        pendingSnapshot = pending
        if snapshotTimeoutTask == nil {
            sendSnapshotRequest(pending)
        }
        return true
    }

    func snapshot(
        minimumRevision: UInt64? = nil,
        persists: Bool = true
    ) async throws -> NoteEditorSnapshotReadyEvent {
        try await withCheckedThrowingContinuation { continuation in
            requestSnapshot(minimumRevision: minimumRevision, persists: persists) { result in
                continuation.resume(with: result)
            }
        }
    }

    @discardableResult
    func receive(_ event: NoteEditorSnapshotReadyEvent) -> Bool {
        guard matchesCurrentDocument(
            protocolVersion: event.protocolVersion,
            documentID: event.documentID,
            documentGeneration: event.documentGeneration
        ), var pending = pendingSnapshot,
           pending.requestID == event.requestID else {
            return false
        }

        let requiredRevision = max(pending.minimumRevision, currentRevision)
        guard event.revision >= requiredRevision else {
            pending.minimumRevision = requiredRevision
            pendingSnapshot = pending
            sendSnapshotRequest(pending)
            return false
        }

        pendingSnapshot = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        if pending.persists {
            cancelScheduledSnapshots()
            currentRevision = event.revision
            dirty = dirty || currentRevision != savedRevision
            onSnapshotAccepted(event)
        }
        pending.completions.forEach { $0(.success(event)) }
        return true
    }

    @discardableResult
    func markSaved(revision: UInt64, as status: NoteSaveStatus) -> Bool {
        guard revision <= currentRevision else { return false }
        savedRevision = max(savedRevision, revision)
        dirty = currentRevision != savedRevision
        adoptSaveStatus(dirty ? .saving : status)
        return true
    }

    func markSaveFailed(documentID: String) {
        guard self.documentID == documentID else { return }
        adoptSaveStatus(.failed)
    }

    func markExternallyModified(documentID: String) {
        guard self.documentID == documentID else { return }
        adoptSaveStatus(.externallyModified)
    }

    private func adoptSaveStatus(_ status: NoteSaveStatus) {
        guard saveStatus != status else { return }
        saveStatus = status
    }

    private func sendSnapshotRequest(_ pending: PendingSnapshot) {
        let requestID = pending.requestID
        if snapshotTimeoutTask == nil {
            let timeout = snapshotTimeout
            snapshotTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, !Task.isCancelled, var pending = pendingSnapshot,
                      pending.requestID == requestID else { return }
                snapshotTimeoutTask = nil
                let completions = pending.completions
                pending.completions.removeAll()
                // Keep a late reply eligible for saving after its callers stop waiting.
                pendingSnapshot = pending.persists ? pending : nil
                completions.forEach { $0(.failure(.snapshotTimedOut)) }
            }
        }
        onSnapshotRequest?(
            NoteEditorSnapshotRequest(
                requestID: requestID,
                documentID: documentID,
                documentGeneration: documentGeneration,
                minimumRevision: pending.minimumRevision,
                type: .requestSnapshot,
                payload: NoteEditorEmptyPayload()
            )
        )
    }

    private func failPendingSnapshot(with error: NoteEditingSessionError) {
        let completions = pendingSnapshot?.completions ?? []
        pendingSnapshot = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        completions.forEach { $0(.failure(error)) }
    }

    private func scheduleSnapshot() {
        idleSnapshotTask?.cancel()
        idleSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: idleSnapshotDelay)
            guard !Task.isCancelled else { return }
            idleSnapshotTask = nil
            _ = requestSnapshot()
        }
        guard maximumAgeSnapshotTask == nil else { return }
        maximumAgeSnapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: maximumSnapshotAge)
            guard !Task.isCancelled else { return }
            maximumAgeSnapshotTask = nil
            _ = requestSnapshot()
        }
    }

    private func cancelScheduledSnapshots() {
        idleSnapshotTask?.cancel()
        maximumAgeSnapshotTask?.cancel()
        idleSnapshotTask = nil
        maximumAgeSnapshotTask = nil
    }

    private func matchesCurrentDocument(
        protocolVersion: Int,
        documentID: String,
        documentGeneration: UInt64
    ) -> Bool {
        protocolVersion == NoteEditorBridgeProtocol.version
            && documentID == self.documentID
            && documentGeneration == self.documentGeneration
    }
}
