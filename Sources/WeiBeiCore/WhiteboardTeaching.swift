import Foundation

public struct WhiteboardStudentEvent: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var questionID: String?
    public var keypointIndex: Int?
    public var question: String
    public var answer: String
    public var correct: Bool?
    public var response = ""
    public init(id: UUID = UUID(), questionID: String? = nil, keypointIndex: Int?, question: String, answer: String, correct: Bool? = nil) {
        self.id = id; self.questionID = questionID; self.keypointIndex = keypointIndex
        self.question = question; self.answer = answer; self.correct = correct
    }
}

/// Actual provider usage, including cancelled and discarded requests. Missing usage is not zero.
public struct WhiteboardTeachingRequest: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var kind: String
    public var keypointIndex: Int?
    public var requestBytes: Int
    public var seconds = 0.0
    public var usage: NativeTokenUsage?
    public var outcome = "running"
    public var skippedLines = 0
    public var diagnostics: [String] = []
}

extension WhiteboardSession {
    public var generatedKeyPoints: Set<Int> {
        Set(lesson.actions.filter { $0.type == .keypointComplete }.compactMap(\.index))
    }
    public var nextKeyPoint: Int? { keyPoints.indices.first { !generatedKeyPoints.contains($0) } }
    public var nextBoardUID: Int { (lesson.actions.flatMap(\.leaves).compactMap(\.boardUID) + discussions.compactMap { $0.card?.boardUID }).max().map { $0 + 1 } ?? 0 }
    public var hasTeachingContent: Bool {
        lesson.actions.prefix(cursor + 1).flatMap(\.leaves).contains { $0.type == .board || $0.type == .graph }
    }

    /// Prefetch at the last playing group. Never queue a second unseen teaching segment.
    public func canPrefetch(inFlight: Bool) -> Bool {
        !generationComplete && !lesson.actions.dropFirst(cursor + (inFlight ? 1 : 0)).contains {
            $0.type != .sessionReady && $0.type != .keypointComplete
        }
    }

    /// The ACK-owned action is immutable; only undispatched actions are retractable.
    public mutating func retractUpcoming(inFlight: Bool) {
        let end = min(lesson.actions.count, cursor + (inFlight ? 1 : 0))
        lesson.actions.removeSubrange(end...)
        generationComplete = nextKeyPoint == nil && !keyPoints.isEmpty
    }

    public mutating func recordQuestion(_ discussion: WhiteboardDiscussion) {
        discussions.append(discussion)
        studentEvents = (studentEvents ?? []) + [.init(id: discussion.id,
            keypointIndex: currentAction?.keypointIndex, question: discussion.question, answer: "")]
    }
    public mutating func finishDiscussion(_ id: UUID) {
        guard let index = discussions.firstIndex(where: { $0.id == id }) else { return }
        discussions[index].completed = true
        if let event = studentEvents?.firstIndex(where: { $0.id == id || (discussions[index].correctionFor != nil && $0.questionID == discussions[index].correctionFor) }) {
            studentEvents?[event].response = discussions[index].text
        }
    }
}
