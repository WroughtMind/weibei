import Foundation

extension WhiteboardSession {
    /// Persist the receipt before starting a reply, so retrying or restoring cannot react twice.
    public mutating func recordAnswer(_ text: String, to action: WhiteboardAction, correct: Bool?) -> WhiteboardDiscussion? {
        guard presentedQuestionIDs.contains(action.stepID), lesson.actions.flatMap(\.leaves).contains(action),
              answers[action.stepID] == nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        answers[action.stepID] = text
        studentEvents = (studentEvents ?? []) + [.init(questionID: action.stepID, keypointIndex: action.keypointIndex,
            question: action.question ?? "", answer: text, correct: correct)]
        guard action.mode == .choice, correct == false,
              !discussions.contains(where: { $0.correctionFor == action.stepID }),
              let index = action.correctIndex, let options = action.options, options.indices.contains(index) else { return nil }
        let context = "题目：\(action.question ?? "")\n学生所选：\(text)\n正确答案：\(options[index])\n解析：\(action.explanation ?? "")"
        let discussion = WhiteboardDiscussion(stepID: currentAction?.stepID ?? "finished", question: context,
            insertionCursor: cursor, correctionFor: action.stepID)
        discussions.append(discussion)
        return discussion
    }
}
