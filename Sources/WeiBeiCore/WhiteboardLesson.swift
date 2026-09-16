import Foundation

public struct WhiteboardFailure: LocalizedError, Sendable {
    public var errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct WhiteboardSource: Codable, Equatable, Sendable {
    public var itemID: String
    public var title: String
    public var pages: [Page]
    public struct Page: Codable, Equatable, Sendable {
        public var number: Int
        public var text: String
        public init(number: Int, text: String) { self.number = number; self.text = text }
    }
    public init(itemID: String, title: String, pages: [Page]) {
        self.itemID = itemID; self.title = title; self.pages = pages
    }
}

/// One newline-delimited JSON action. A group is one atomic dispatch with child completion barriers.
public struct WhiteboardAction: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case board, speak, graph, highlight, circle, ask, group, newPage = "new_page", newColumn = "new_column"
        case sessionReady = "session_ready", keypointComplete = "keypoint_complete"
    }
    public enum CardType: String, Codable, Sendable { case definition, formula, example, diagram, summary }
    public enum QuestionMode: String, Codable, Sendable { case choice, open }
    public struct Rect: Codable, Equatable, Sendable { public var x, y, w, h: Double }
    public var keyPoints: [String]?
    public var index: Int?
    public var pageID: String?
    public var type: Kind
    public var stepID: String
    public var title: String?
    public var boardUID: Int?
    public var cardType: CardType?
    public var markdown: String?
    public var mermaid: String?
    public var text: String?
    public var sourcePage: Int?
    public var targetBoardID: Int?
    public var snippet: String?
    public var rect: Rect?
    public var color: String?
    public var mode: QuestionMode?
    public var question: String?
    public var options: [String]?
    public var correctIndex: Int?
    public var explanation: String?
    public var actions: [WhiteboardAction]?
    public var id: String { stepID }
    public var leaves: [WhiteboardAction] { type == .group ? actions ?? [] : [self] }
    public var narration: String { leaves.compactMap(\.text).joined(separator: "\n") }
    public var questionAction: WhiteboardAction? { leaves.first { $0.type == .ask } }
    public var label: String { title ?? leaves.compactMap(\.title).first ?? question ?? String(narration.prefix(40)) }
    enum CodingKeys: String, CodingKey {
        case type, title, mermaid, snippet, rect, color, question, options, explanation, actions, mode, index
        case keyPoints = "key_points"
        case markdown = "board_content", text = "spoken_text", pageID = "page_id"
        case stepID = "step_id", boardUID = "board_uid", cardType = "card_type", sourcePage = "source_page"
        case targetBoardID = "target_board_id", correctIndex = "correct_index"
    }
}

public struct WhiteboardLesson: Codable, Equatable, Sendable {
    public var title: String
    public var actions: [WhiteboardAction]
    public init(title: String, actions: [WhiteboardAction] = []) { self.title = title; self.actions = actions }

    public func validate(source: WhiteboardSource) throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw WhiteboardFailure("课堂动作无效：" + message) }
        }
        try check(!title.isEmpty && title.count <= 200 && actions.count <= 160, "标题或动作数量超限")
        var ids = Set<String>(), boards = Set<Int>(), pageIDs = Set<String>()
        var page = 0, boardPages: [Int: Int] = [:], completedPoints = Set<Int>(), outlineSeen = false
        let outline = actions.first { $0.type == .sessionReady }
        for root in actions {
            let children = root.type == .group ? root.actions ?? [] : [root]
            if root.type == .group {
                try check(!root.stepID.isEmpty && root.stepID.count <= 80 && ids.insert(root.stepID).inserted, "重复动作编号")
                try check((1...8).contains(children.count) && children.allSatisfy { ![.group, .newPage, .newColumn, .sessionReady, .keypointComplete].contains($0.type) }, "组合动作不能嵌套或改变页面及关键点")
                try check(children.filter { $0.type == .speak }.count <= 1 && children.filter { $0.type == .ask }.count <= 1, "组合内只能有一段语音和一道提问")
                try check(children.filter { $0.type == .board || $0.type == .graph }.count <= 2, "一组最多两张对照板书")
            }
            for a in children {
                try check(!a.stepID.isEmpty && a.stepID.count <= 80 && ids.insert(a.stepID).inserted, "动作编号必须唯一")
                for text in [a.title, a.markdown, a.mermaid, a.text, a.question, a.explanation, a.snippet].compactMap({ $0 }) {
                    try check(text.count <= 8_000, "单个动作文本过长")
                }
                if let number = a.sourcePage { try check(source.pages.contains { $0.number == number }, "引用未提供的原文页") }
                switch a.type {
                case .sessionReady:
                    try check(!outlineSeen && a == root, "课堂只能有一份关键点清单")
                    outlineSeen = true
                    try check((3...6).contains(a.keyPoints?.count ?? 0) && a.keyPoints!.allSatisfy { !$0.isEmpty && $0.count <= 80 }, "关键点应为 3–6 条简短目标")
                case .keypointComplete:
                    guard let index = a.index else { throw WhiteboardFailure("缺少关键点编号") }
                    try check(page > 0 && index == page - 1 && (outline?.keyPoints?.indices.contains(index) == true)
                        && completedPoints.insert(index).inserted, "关键点编号与当前页不符或重复")
                case .newPage:
                    page += 1; try check(page <= 12, "页面过多")
                    try check(pageIDs.insert(a.pageID ?? a.stepID).inserted, "页面编号重复")
                case .newColumn: try check(page > 0, "请先创建页面")
                case .board, .graph:
                    try check(page > 0 && a.sourcePage != nil, "板书缺少页面或来源")
                    guard let id = a.boardUID else { throw WhiteboardFailure("板书缺少 board_uid") }
                    try check(id >= 0 && id <= 1_000_000 && boards.insert(id).inserted, "重复板书编号")
                    boardPages[id] = page
                    try check((a.markdown?.count ?? 0) <= 1_200, "每张板书最多 1,200 字")
                    try check(a.type == .board ? !(a.markdown ?? "").isEmpty : !(a.mermaid ?? "").isEmpty, "板书内容为空")
                case .speak:
                    try check(!(a.text ?? "").isEmpty, "讲稿为空")
                    try check((a.text?.count ?? 0) <= 600, "每段讲稿最多 600 字")
                case .highlight, .circle:
                    try check(a.targetBoardID.flatMap { boardPages[$0] } == page, "标注目标不在当前页或尚未出现")
                    try check(a.color == nil || ["red", "green", "blue", "ink"].contains(a.color!), "标注颜色无效")
                    if let r = a.rect {
                        try check([r.x, r.y, r.w, r.h].allSatisfy { $0.isFinite && (0...1).contains($0) }
                            && r.w > 0 && r.h > 0 && r.x + r.w <= 1.001 && r.y + r.h <= 1.001, "标注坐标无效")
                    } else { try check(!(a.snippet ?? "").isEmpty, "缺少标注文字或位置") }
                case .ask:
                    try check(!(a.question ?? "").isEmpty && !(a.explanation ?? "").isEmpty, "缺少问题或解析")
                    let options = a.options ?? []
                    try check(options.count <= 4 && options.allSatisfy { !$0.isEmpty && $0.count <= 500 }, "选项无效")
                    try check(a.mode != nil, "缺少提问模式")
                    if a.mode == .choice { try check(options.count >= 2 && a.correctIndex.map(options.indices.contains) == true, "答案索引无效") }
                    else { try check(options.isEmpty && a.correctIndex == nil, "开放题不能含选项答案") }
                case .group: throw WhiteboardFailure("不支持嵌套组合动作")
                }
            }
        }
    }
}

/// Streaming parser keeps an incomplete JSON line until the next chunk. No brace guessing.
public struct WhiteboardActionDecoder: Sendable {
    private var pending = ""
    private var count = 0
    public init() {}
    public mutating func append(_ delta: String, final: Bool = false) throws -> [WhiteboardAction] {
        pending += delta; count += delta.utf8.count
        guard count <= 512_000 else { throw WhiteboardFailure("课堂动作流超过上限，请减少材料范围。") }
        var lines: [String] = []
        while let end = pending.firstIndex(of: "\n") {
            lines.append(String(pending[..<end])); pending = String(pending[pending.index(after: end)...])
        }
        if final && !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(pending); pending = ""
        }
        return try lines.compactMap { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            do { return try JSONDecoder().decode(WhiteboardAction.self, from: Data(line.utf8)) }
            catch { throw WhiteboardFailure("模型返回了无效的独立 JSON 动作，已停止接收。") }
        }
    }
}

/// Exactly one in-flight action. Only a matching, successful ACK can advance the cursor.
public struct WhiteboardActionGate: Equatable, Sendable {
    public private(set) var cursor: Int
    public private(set) var pendingID: String?
    public private(set) var ticket: UUID?
    public init(cursor: Int = 0) { self.cursor = cursor }
    public mutating func dispatch(_ actions: [WhiteboardAction]) -> (WhiteboardAction, UUID)? {
        guard pendingID == nil, actions.indices.contains(cursor) else { return nil }
        let action = actions[cursor]; let token = UUID()
        pendingID = action.stepID; ticket = token
        return (action, token)
    }
    @discardableResult
    public mutating func acknowledge(stepID: String, ticket: UUID, success: Bool) -> Bool {
        guard pendingID == stepID && self.ticket == ticket else { return false }
        guard success else { return false }
        cursor += 1; pendingID = nil; self.ticket = nil
        return true
    }
    public mutating func retry() { pendingID = nil; ticket = nil }
}

/// Persistent content and measured layout; animation and playback handles never enter this snapshot.
public struct WhiteboardCanvasState: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var id, kind: String
        public var x, y, w, h: Double
        public var columnIndex: Int
        public var boardUid: Int
        public var keypoint: Keypoint?
        public var mermaidGraph: Graph?
        public var decorations: [WhiteboardAction]
    }
    public struct Keypoint: Codable, Equatable, Sendable { public var title, content, type: String }
    public struct Graph: Codable, Equatable, Sendable { public var source: String }
    public struct Column: Codable, Equatable, Sendable { public var w, nextY: Double }
    public struct Layout: Codable, Equatable, Sendable {
        public struct Parameters: Codable, Equatable, Sendable { public var tileW: Double }
        public var columns: [Column]
        public var activeIndex: Int
        public var lp: Parameters
    }
    public struct InkPoint: Codable, Equatable, Sendable { public var x, y: Double }
    public struct InkStroke: Codable, Equatable, Sendable { public var id: String; public var points: [InkPoint] }
    public struct Page: Codable, Equatable, Sendable {
        public var id, title: String
        public var overlayItems: [Item]
        public var columnLayout: Layout
        public var strokes: [InkStroke]?
    }
    public var version: Int
    public var revision: Int
    public var activePageId: String?
    public var zoom, scrollX, scrollY: Double?
    public var pages: [Page]
}

public struct WhiteboardDiscussion: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var stepID: String
    public var question: String
    public var text = ""
    public var card: WhiteboardAction?
    public var insertionCursor: Int
    public var completed = false
    public var correctionFor: String?
    public init(stepID: String, question: String, insertionCursor: Int, correctionFor: String? = nil) {
        self.stepID = stepID; self.question = question; self.insertionCursor = insertionCursor
        self.correctionFor = correctionFor
    }
}

public struct WhiteboardSession: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var source: WhiteboardSource
    public var goal: String
    public var lesson: WhiteboardLesson
    public var cursor = 0
    public var generationComplete = false
    public var generatedPages = 0
    public var presentedQuestionIDs: [String] = []
    public var answers: [String: String] = [:]
    public var discussions: [WhiteboardDiscussion] = []
    public var canvas: WhiteboardCanvasState?
    public var updatedAt = Date()
    public init(source: WhiteboardSource, goal: String, lesson: WhiteboardLesson) {
        self.source = source; self.goal = goal; self.lesson = lesson
    }
    public var keyPoints: [String] { lesson.actions.first(where: { $0.type == .sessionReady })?.keyPoints ?? [] }
    public var completedKeyPoints: Set<Int> { Set(lesson.actions.prefix(cursor).flatMap(\.leaves).filter { $0.type == .keypointComplete }.compactMap(\.index)) }
    public var questions: [WhiteboardAction] {
        let shown = lesson.actions.flatMap(\.leaves).filter { $0.type == .ask && presentedQuestionIDs.contains($0.stepID) }
        return shown.filter { answers[$0.stepID] == nil } + shown.filter { answers[$0.stepID] != nil }
    }
    public var completed: Bool { generationComplete && cursor == lesson.actions.count }
    public var currentAction: WhiteboardAction? { lesson.actions.indices.contains(cursor) ? lesson.actions[cursor] : nil }
    public func validated() throws -> Self {
        try lesson.validate(source: source)
        guard (0...lesson.actions.count).contains(cursor) else { throw WhiteboardFailure("课堂进度损坏，原记录已保留。") }
        if let canvas {
            let items = canvas.pages.flatMap(\.overlayItems)
            let strokes = canvas.pages.flatMap { $0.strokes ?? [] }
            guard canvas.version == 1, canvas.revision >= 0, canvas.pages.count <= 160, items.count <= 256,
                  (0.5...2).contains(canvas.zoom ?? 1),
                  [canvas.scrollX ?? 0, canvas.scrollY ?? 0].allSatisfy({ $0.isFinite && (0...2_000_000).contains($0) }),
                  Set(canvas.pages.map(\.id)).count == canvas.pages.count,
                  Set(strokes.map(\.id)).count == strokes.count, strokes.count <= 2_000,
                  strokes.reduce(0, { $0 + $1.points.count }) <= 200_000,
                  strokes.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.points.isEmpty && $0.points.allSatisfy {
                      $0.x.isFinite && $0.y.isFinite && (0...1_000_000).contains($0.x) && (0...1_000_000).contains($0.y)
                  }}),
                  canvas.pages.allSatisfy({ (260...360).contains($0.columnLayout.lp.tileW) }),
                  canvas.activePageId == nil || canvas.pages.contains(where: { $0.id == canvas.activePageId }),
                  items.allSatisfy({ card in
                      [card.x, card.y, card.w, card.h].allSatisfy { $0.isFinite && (0...1_000_000).contains($0) }
                          && card.w > 0 && card.h > 0 && (0...1).contains(card.columnIndex)
                  })
            else { throw WhiteboardFailure("画布布局损坏，原记录已保留。") }
        }
        guard (0...6).contains(generatedPages) else { throw WhiteboardFailure("课堂页面进度损坏。") }
        for discussion in discussions {
            guard (0...lesson.actions.count).contains(discussion.insertionCursor), discussion.text.count <= 32_000 else {
                throw WhiteboardFailure("追问存档损坏。")
            }
            if let card = discussion.card {
                guard card.type == .board else { throw WhiteboardFailure("补充板书类型无效。") }
                // Validate the same source/content boundary as main-lesson cards, in an explicit page context.
                var page = lesson.actions.first { $0.type == .newPage }
                page?.stepID = "supplement-page"
                if let page { try WhiteboardLesson(title: "补充", actions: [page, card]).validate(source: source) }
                else { throw WhiteboardFailure("补充板书缺少课堂页面。") }
            }
        }
        return self
    }
    public func markdown() -> String {
        var result = "# \(lesson.title)\n\n来源：\(source.title)\n\n学习目标：\(goal)\n"
        for a in lesson.actions.flatMap(\.leaves) {
            switch a.type {
            case .newPage: result += "\n## \(a.title ?? "板书")\n"
            case .board: result += "\n### \(a.title ?? "")\n\n\(a.markdown ?? "")\n"
            case .graph: result += "\n```mermaid\n\(a.mermaid ?? "")\n```\n"
            case .speak: result += "\n\(a.text ?? "")\n"
            case .ask: result += "\n自测：\(a.question ?? "")\n\n回答：\(answers[a.stepID] ?? "尚未作答")\n\n解析：\(a.explanation ?? "")\n"
            default: break
            }
            if let page = a.sourcePage { result += "\n来源：第 \(page) 页\n" }
        }
        for d in discussions {
            result += "\n## 追问：\(d.question)\n\n" + d.text
            if let card = d.card { result += "\n\n" + (card.markdown ?? "") }
        }
        return result
    }
}

public struct WhiteboardSessionStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    public func save(_ session: WhiteboardSession) throws {
        _ = try session.validated()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: url(session.id), options: .atomic)
    }
    public func load(_ id: UUID) throws -> WhiteboardSession {
        try JSONDecoder().decode(WhiteboardSession.self, from: Data(contentsOf: url(id))).validated()
    }
    public func list(itemID: String) throws -> [WhiteboardSession] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var sessions: [WhiteboardSession] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            let session = try load(id)
            if session.source.itemID == itemID { sessions.append(session) }
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }
}
