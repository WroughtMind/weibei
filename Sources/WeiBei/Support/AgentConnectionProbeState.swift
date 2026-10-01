import Foundation

/// A result belongs to the credential revision that was checked. Editing a credential
/// invalidates both the visible result and any older request still completing.
struct AgentConnectionProbeState {
    struct Mark: Equatable {
        var text: String
        var ok: Bool
    }
    private(set) var marks: [UUID: Mark] = [:]
    private(set) var probingProfileID: UUID?
    private var requests: [UUID: UUID] = [:]

    mutating func begin(_ profileID: UUID) -> UUID {
        let requestID = UUID()
        marks[profileID] = nil
        requests = [profileID: requestID]
        probingProfileID = profileID
        return requestID
    }

    mutating func invalidate(_ profileID: UUID) {
        marks[profileID] = nil
        requests[profileID] = nil
        if probingProfileID == profileID { probingProfileID = nil }
    }

    mutating func invalidateAll() {
        marks.removeAll()
        requests.removeAll()
        probingProfileID = nil
    }

    func isCurrent(_ profileID: UUID, requestID: UUID) -> Bool {
        requests[profileID] == requestID
    }

    mutating func complete(_ profileID: UUID, requestID: UUID, mark: Mark) {
        guard requests[profileID] == requestID else { return }
        requests[profileID] = nil
        marks[profileID] = mark
        if probingProfileID == profileID { probingProfileID = nil }
    }
}
