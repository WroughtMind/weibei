import Combine
import Foundation

enum NoteSaveStatus: Equatable {
    case idle
    case saving
    case writtenToFile
    case savedInWeiBei
    case failed
    case externallyModified

    /// 失败和冲突立刻显示。`.saving` 本身不占标题栏，持续过久才由会话单独亮出。
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
        var completions: [SnapshotCompletion]
    }

    private var onSnapshotRequest: ((NoteEditorSnapshotRequest) -> Void)?
    private var snapshotRequestHandlerToken: UUID?
    private let onSnapshotAccepted: (NoteEditorSnapshotReadyEvent) -> Void
    private var pendingSnapshot: PendingSnapshot?
    private var idleSnapshotTask: Task<Void, Never>?
    private var maximumAgeSnapshotTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?
    private let idleSnapshotDelay: Duration
    private let maximumSnapshotAge: Duration
    private let snapshotTimeout: Duration
    private let savingLabelDelay: Duration
    private var savingLabelTask: Task<Void, Never>?

    private(set) var documentID: String
    private(set) var documentGeneration: UInt64
    private(set) var currentRevision: UInt64
    private(set) var savedRevision: UInt64
    private(set) var dirty = false
    @Published private(set) var saveStatus: NoteSaveStatus = .idle
    /// 「保存中」持续超过 `savingLabelDelay` 才为真；失败和冲突不走这条延迟。
    @Published private(set) var showsProlongedSavingLabel = false

    init(
        documentID: String,
        initialRevision: UInt64 = 0,
        idleSnapshotDelay: Duration = .milliseconds(850),
        maximumSnapshotAge: Duration = .seconds(5),
        snapshotTimeout: Duration = .seconds(5),
        savingLabelDelay: Duration = .seconds(2),
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
        self.savingLabelDelay = savingLabelDelay
        self.onSnapshotRequest = onSnapshotRequest
        snapshotRequestHandlerToken = onSnapshotRequest == nil ? nil : UUID()
        self.onSnapshotAccepted = onSnapshotAccepted
    }

    @discardableResult
    func bindSnapshotRequestHandler(
        _ handler: @escaping (NoteEditorSnapshotRequest) -> Void
    ) -> UUID {
        failPendingSnapshot(with: .bridgeUnavailable)
        let token = UUID()
        snapshotRequestHandlerToken = token
        onSnapshotRequest = handler
        return token
    }

    func unbindSnapshotRequestHandler(_ token: UUID) {
        guard snapshotRequestHandlerToken == token else { return }
        snapshotRequestHandlerToken = nil
        onSnapshotRequest = nil
        failPendingSnapshot(with: .bridgeUnavailable)
        cancelScheduledSnapshots()
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
        completion: SnapshotCompletion? = nil
    ) -> Bool {
        guard onSnapshotRequest != nil else {
            completion?(.failure(.bridgeUnavailable))
            return false
        }

        let requiredRevision = max(minimumRevision ?? currentRevision, currentRevision)
        if var pendingSnapshot {
            pendingSnapshot.minimumRevision = max(
                pendingSnapshot.minimumRevision,
                requiredRevision
            )
            if let completion {
                pendingSnapshot.completions.append(completion)
            }
            self.pendingSnapshot = pendingSnapshot
            return true
        }

        return issueSnapshotRequest(
            minimumRevision: requiredRevision,
            completions: completion.map { [$0] } ?? []
        )
    }

    func snapshot(
        minimumRevision: UInt64? = nil
    ) async throws -> NoteEditorSnapshotReadyEvent {
        try await withCheckedThrowingContinuation { continuation in
            requestSnapshot(minimumRevision: minimumRevision) { result in
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
        ), let pendingSnapshot,
           pendingSnapshot.requestID == event.requestID else {
            return false
        }

        guard event.revision >= pendingSnapshot.minimumRevision else {
            self.pendingSnapshot = nil
            _ = issueSnapshotRequest(
                minimumRevision: pendingSnapshot.minimumRevision,
                completions: pendingSnapshot.completions
            )
            return false
        }

        self.pendingSnapshot = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        cancelScheduledSnapshots()
        currentRevision = max(currentRevision, event.revision)
        dirty = dirty || currentRevision != savedRevision
        onSnapshotAccepted(event)
        pendingSnapshot.completions.forEach { $0(.success(event)) }
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
        let wasSaving = saveStatus == .saving
        saveStatus = status
        guard status == .saving else {
            cancelSavingLabel()
            return
        }
        guard !wasSaving else { return }
        showsProlongedSavingLabel = false
        let delay = savingLabelDelay
        savingLabelTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, saveStatus == .saving else { return }
            showsProlongedSavingLabel = true
        }
    }

    private func cancelSavingLabel() {
        savingLabelTask?.cancel()
        savingLabelTask = nil
        if showsProlongedSavingLabel {
            showsProlongedSavingLabel = false
        }
    }

    @discardableResult
    private func issueSnapshotRequest(
        minimumRevision: UInt64,
        completions: [SnapshotCompletion]
    ) -> Bool {
        guard let onSnapshotRequest else {
            completions.forEach { $0(.failure(.bridgeUnavailable)) }
            return false
        }

        let requestID = UUID().uuidString
        pendingSnapshot = PendingSnapshot(
            requestID: requestID,
            minimumRevision: minimumRevision,
            completions: completions
        )
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: snapshotTimeout)
            guard !Task.isCancelled,
                  pendingSnapshot?.requestID == requestID else { return }
            failPendingSnapshot(with: .snapshotTimedOut)
        }
        onSnapshotRequest(
            NoteEditorSnapshotRequest(
                requestID: requestID,
                documentID: documentID,
                documentGeneration: documentGeneration,
                minimumRevision: minimumRevision,
                type: .requestSnapshot,
                payload: NoteEditorEmptyPayload()
            )
        )
        return true
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
