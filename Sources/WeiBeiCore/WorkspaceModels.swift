import CoreGraphics
import Foundation

public enum WeiBeiInterfaceLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }

    public var settingsLabel: String {
        switch self {
        case .chinese:
            return "中文界面"
        case .english:
            return "English interface"
        }
    }

    public func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .chinese:
            return chinese
        case .english:
            return english
        }
    }
}

public enum StudyItemKind: String, Codable, CaseIterable, Identifiable {
    case html
    case pdf
    case markdown
    case text

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .html:
            return "HTML"
        case .pdf:
            return "PDF"
        case .markdown:
            return "Markdown"
        case .text:
            return language.text("文本", "Text")
        }
    }

    public var systemImage: String {
        switch self {
        case .html: "globe"
        case .pdf: "doc.richtext"
        case .markdown: "note.text"
        case .text: "doc.text"
        }
    }

    public static func detect(from url: URL) -> StudyItemKind {
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            return .html
        case "pdf":
            return .pdf
        case "md", "markdown":
            return .markdown
        default:
            return .text
        }
    }

}

public enum PaneFocus: String, Codable, Hashable {
    case library
    case reader
    case notes
    case agent
}

public enum WorkspacePaneRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case reader
    case agent
    case notes

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .reader:
            return language.text("文档", "Document")
        case .agent:
            return language.text("对话", "Chat")
        case .notes:
            return language.text("笔记", "Notes")
        }
    }

    public func shortLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .reader:
            return language.text("文", "Doc")
        case .agent:
            return language.text("对", "Chat")
        case .notes:
            return language.text("笔", "Notes")
        }
    }

    public var focus: PaneFocus {
        switch self {
        case .reader:
            return .reader
        case .agent:
            return .agent
        case .notes:
            return .notes
        }
    }

    public var systemImage: String {
        switch self {
        case .reader:
            return "doc.text.magnifyingglass"
        case .agent:
            return "bubble.left.and.text.bubble.right"
        case .notes:
            return "square.and.pencil"
        }
    }

    public static var defaultThreePaneOrder: [WorkspacePaneRole] {
        [.reader, .agent, .notes]
    }

    public static func normalized(_ roles: [WorkspacePaneRole]) -> [WorkspacePaneRole] {
        var ordered: [WorkspacePaneRole] = []
        for role in roles where !ordered.contains(role) {
            ordered.append(role)
        }
        for role in WorkspacePaneRole.defaultThreePaneOrder where !ordered.contains(role) {
            ordered.append(role)
        }
        return Array(ordered.prefix(3))
    }
}

public enum ThreePaneReorderTargeting {
    public static func targetIndex(
        order rawOrder: [WorkspacePaneRole],
        frames: [WorkspacePaneRole: CGRect],
        role: WorkspacePaneRole,
        horizontalDelta: CGFloat
    ) -> Int? {
        let order = WorkspacePaneRole.normalized(rawOrder)
        guard let currentIndex = order.firstIndex(of: role),
              let sourceFrame = frames[role] else { return nil }
        let draggedFrame = sourceFrame.offsetBy(dx: horizontalDelta, dy: 0)
        let draggedCenterX = draggedFrame.midX

        let overlapTarget = order.enumerated().compactMap { offset, role -> (offset: Int, overlap: CGFloat, distance: CGFloat)? in
            guard let frame = frames[role] else { return nil }
            let overlap = horizontalOverlap(draggedFrame, frame)
            guard overlap > 0.5 else { return nil }
            return (offset, overlap, abs(frame.midX - draggedCenterX))
        }
        .max { left, right in
            if abs(left.overlap - right.overlap) > 0.5 {
                return left.overlap < right.overlap
            }
            return left.distance > right.distance
        }?.offset

        let targetIndex = overlapTarget ?? order.enumerated().compactMap { offset, role -> (offset: Int, distance: CGFloat)? in
            guard let frame = frames[role] else { return nil }
            return (offset, abs(frame.midX - draggedCenterX))
        }
        .min { $0.distance < $1.distance }?.offset

        return targetIndex == currentIndex ? nil : targetIndex
    }

    private static func horizontalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        Swift.max(0, Swift.min(lhs.maxX, rhs.maxX) - Swift.max(lhs.minX, rhs.minX))
    }
}

public enum WikiLink {
    public static func targetTitle(from rawTitle: String) -> String {
        let target = splitObsidianFields(rawTitle).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteTitle = target
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return noteTitle.isEmpty ? target : noteTitle
    }

    private static func splitObsidianFields(_ raw: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            let nextIndex = raw.index(after: index)
            if character == "\\",
               nextIndex < raw.endIndex,
               raw[nextIndex] == "|" {
                fields.append(current)
                current = ""
                index = raw.index(after: nextIndex)
                continue
            }
            if character == "|" {
                fields.append(current)
                current = ""
                index = nextIndex
                continue
            }
            current.append(character)
            index = nextIndex
        }
        fields.append(current)
        return fields
    }

    public static func enclosingTitle(in text: String, cursor utf16Offset: Int) -> String? {
        let nsText = text as NSString
        let cursor = max(0, min(utf16Offset, nsText.length))
        let start = nsText.range(of: "[[", options: .backwards, range: NSRange(location: 0, length: cursor))
        let end = nsText.range(of: "]]", range: NSRange(location: cursor, length: nsText.length - cursor))
        guard start.location != NSNotFound,
              end.location != NSNotFound,
              start.location + 2 <= end.location else {
            return nil
        }
        let rawTitle = nsText.substring(with: NSRange(location: start.location + 2, length: end.location - start.location - 2))
        let title = targetTitle(from: rawTitle)
        return title.isEmpty ? nil : title
    }
}

public enum SourceReferenceTitle {
    public static func parse(_ raw: String) -> (title: String, pageIndex: Int?) {
        var text = raw
            .components(separatedBy: .newlines)
            .reversed()
            .map(cleanedLine)
            .first(where: { $0.hasPrefix("来源：") || $0.localizedCaseInsensitiveContains("source:") })
            ?? cleanedLine(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("来源：") {
            text = String(text.dropFirst("来源：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.lowercased().hasPrefix("source:") {
            text = String(text.dropFirst("source:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let range = text.range(of: #"(?:，第\s*\d+\s*页|,\s*page\s*\d+)$"#, options: [.regularExpression, .caseInsensitive]) else {
            return (text, nil)
        }
        let suffix = text[range]
        let pageNumber = Int(suffix.filter(\.isNumber))
        let title = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, pageNumber.map { max($0 - 1, 0) })
    }

    private static func cleanedLine(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

public enum WorkspaceLayout: String, Codable, CaseIterable, Identifiable {
    case documentAgentNotes
    case documentNotesAgent
    case documentNotesSplit
    case immersiveReading
    case immersiveConversation
    case immersiveWriting

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .documentAgentNotes:
            return language.text("阅读-对话-笔记", "Reader-Chat-Notes")
        case .documentNotesAgent:
            return language.text("阅读-笔记-对话", "Reader-Notes-Chat")
        case .documentNotesSplit:
            return language.text("阅读/笔记对半", "Reader / Notes")
        case .immersiveReading:
            return language.text("沉浸阅读", "Immersive Reading")
        case .immersiveConversation:
            return language.text("沉浸对话", "Immersive Chat")
        case .immersiveWriting:
            return language.text("沉浸写笔记", "Immersive Writing")
        }
    }

    public var hasCollapsibleRightPane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit, .immersiveConversation, .immersiveWriting:
            return true
        case .immersiveReading:
            return false
        }
    }

    public var isDocumentThreePane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveConversation, .immersiveWriting:
            return false
        }
    }

    public var allowsRailOnlyPanes: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return true
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return false
        }
    }

    public var defaultThreePaneOrder: [WorkspacePaneRole]? {
        switch self {
        case .documentAgentNotes:
            return [.reader, .agent, .notes]
        case .documentNotesAgent:
            return [.reader, .notes, .agent]
        case .documentNotesSplit, .immersiveReading, .immersiveConversation, .immersiveWriting:
            return nil
        }
    }

    public var systemImage: String {
        switch self {
        case .documentAgentNotes:
            return "rectangle.split.3x1"
        case .documentNotesAgent:
            return "rectangle.split.3x1.fill"
        case .documentNotesSplit:
            return "rectangle.split.2x1"
        case .immersiveReading:
            return "doc.text.magnifyingglass"
        case .immersiveConversation:
            return "bubble.left.and.text.bubble.right"
        case .immersiveWriting:
            return "square.and.pencil"
        }
    }

    public var hasPrimaryAgentPane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .immersiveConversation:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveWriting:
            return false
        }
    }
}

public enum AgentSurface: String, Codable, CaseIterable, Identifiable {
    case bottomDrawer
    case cornerPanel
    case selectionFloat
    case quietInsight
    case hidden

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .bottomDrawer:
            return language.text("底部对话栏", "Bottom Chat")
        case .cornerPanel:
            return language.text("右下轻问", "Corner Ask")
        case .selectionFloat:
            return language.text("选区轻提示", "Selection Prompt")
        case .quietInsight:
            return language.text("页边洞察", "Margin Insight")
        case .hidden:
            return language.text("隐藏对话", "Hide Chat")
        }
    }

    public func actionLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .hidden:
            return label(language: language)
        default:
            return language.text("使用\(label(language: language))", "Use \(label(language: language))")
        }
    }
}

public enum NoteRenderMode: String, Codable, CaseIterable, Identifiable {
    case rich
    case split
    case source
    case preview

    public var id: String { rawValue }
    public static let visibleCases: [NoteRenderMode] = [.rich, .split, .source]

    public var visibleMode: NoteRenderMode {
        self == .preview ? .rich : self
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .rich:
            return language.text("写作", "Write")
        case .split:
            return language.text("对照", "Compare")
        case .source:
            return language.text("源码", "Source")
        case .preview:
            return language.text("预览", "Preview")
        }
    }
}

public struct NoteEditorCommand: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        case replaceSelection
        case applyAgentPatch
        case insertMarkdown
        case scrollToHeading
    }

    public var id: UUID
    public var kind: Kind
    public var markdown: String

    public init(id: UUID = UUID(), kind: Kind, markdown: String) {
        self.id = id
        self.kind = kind
        self.markdown = markdown
    }
}

public enum SelectionSource: String, Codable, Hashable {
    case document
    case note
}

public struct SelectionContext: Identifiable, Codable, Hashable {
    public var id: UUID
    public var text: String
    public var source: SelectionSource
    public var ownerTitle: String
    public var isEditable: Bool

    public init(id: UUID = UUID(), text: String, source: SelectionSource, ownerTitle: String, isEditable: Bool = true) {
        self.id = id
        self.text = text
        self.source = source
        self.ownerTitle = ownerTitle
        self.isEditable = isEditable
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch source {
        case .document:
            return language.text("文档选区：\(ownerTitle)", "Document selection: \(ownerTitle)")
        case .note:
            return language.text("笔记选区：\(ownerTitle)", "Note selection: \(ownerTitle)")
        }
    }

    public var isNoteSelection: Bool {
        source == .note
    }

    public var isReplaceableNoteSelection: Bool {
        source == .note && isEditable
    }
}

public enum SelectionAttachmentMerge {
    public static func mergedText(existing: String, incoming: String, withinSelectionGesture: Bool) -> String? {
        let existingText = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingText = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExisting = normalized(existingText)
        let normalizedIncoming = normalized(incomingText)
        guard !normalizedExisting.isEmpty, !normalizedIncoming.isEmpty else { return nil }
        if normalizedExisting.contains(normalizedIncoming) { return existingText }
        if normalizedIncoming.contains(normalizedExisting) { return incomingText }
        guard withinSelectionGesture else { return nil }
        if let merged = overlappedText(existingText, incomingText) {
            return merged
        }
        guard canStitchAdjacentText(existingText, incomingText) else { return nil }
        return existingText + incomingText
    }

    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined()
    }

    public static func containsSelection(_ container: String, fragment: String) -> Bool {
        let normalizedContainer = normalized(container)
        let normalizedFragment = normalized(fragment)
        guard !normalizedContainer.isEmpty, !normalizedFragment.isEmpty else { return false }
        return normalizedContainer.contains(normalizedFragment)
    }

    private static func overlappedText(_ existing: String, _ incoming: String) -> String? {
        let maxLength = min(existing.count, incoming.count)
        guard maxLength > 0 else { return nil }
        for length in stride(from: maxLength, through: 1, by: -1) {
            let suffix = existing.suffix(length)
            let prefix = incoming.prefix(length)
            if suffix == prefix {
                return existing + incoming.dropFirst(length)
            }
            let incomingSuffix = incoming.suffix(length)
            let existingPrefix = existing.prefix(length)
            if incomingSuffix == existingPrefix {
                return incoming + existing.dropFirst(length)
            }
        }
        return nil
    }

    private static func canStitchAdjacentText(_ existing: String, _ incoming: String) -> Bool {
        let blockedPrefixes = ["#", ">", "-", "*", "|", "```", "$$", "!["]
        guard !blockedPrefixes.contains(where: incoming.hasPrefix) else { return false }
        guard !existing.hasSuffix("\n"), !incoming.hasPrefix("\n") else { return false }
        let terminal = CharacterSet(charactersIn: "。！？!?；;：:")
        guard let last = existing.unicodeScalars.last else { return false }
        return !terminal.contains(last) || incoming.count <= 12
    }
}

public struct FloatingAgentCoordinate: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SelectionAnchorCoordinate {
    public static func y(_ contentY: Double, contentHeight: Double, contentViewIsFlipped: Bool) -> Double {
        contentViewIsFlipped ? contentY : contentHeight - contentY
    }
}

public enum SelectionFloatingAgentPlacement {
    public static let expandedHalfWidth = 156.0
    public static let compactHalfWidth = 82.0

    public static func isVisible(
        surface: AgentSurface,
        hasSelection: Bool,
        hasAnchor: Bool,
        pinned: Bool
    ) -> Bool {
        surface == .selectionFloat && hasSelection && (hasAnchor || pinned)
    }

    public static func position(
        anchor: FloatingAgentCoordinate?,
        canvas: FloatingAgentCoordinate,
        topInset: Double = 0,
        surfaceHalfWidth: Double = expandedHalfWidth,
        prefersAnchorCenter: Bool = false
    ) -> FloatingAgentCoordinate {
        let edgePadding = 18.0
        let anchorGap = 10.0
        let verticalGap = 8.0
        let contentCanvas = FloatingAgentCoordinate(x: canvas.x, y: max(1, canvas.y - topInset))
        let fallback = FloatingAgentCoordinate(x: contentCanvas.x - 128, y: contentCanvas.y - 124)
        let anchor = anchor.map { FloatingAgentCoordinate(x: $0.x, y: max(0, $0.y - topInset)) } ?? fallback
        let minimumX = surfaceHalfWidth + edgePadding
        let maximumX = contentCanvas.x - surfaceHalfWidth - edgePadding
        let rightSideX = anchor.x + surfaceHalfWidth + anchorGap
        let leftSideX = anchor.x - surfaceHalfWidth - anchorGap
        let preferredX: Double
        if prefersAnchorCenter {
            preferredX = anchor.x
        } else if rightSideX <= maximumX {
            preferredX = rightSideX
        } else if leftSideX >= minimumX {
            preferredX = leftSideX
        } else {
            preferredX = anchor.x
        }
        return FloatingAgentCoordinate(
            x: clamp(preferredX, min: minimumX, max: maximumX),
            y: clamp(anchor.y + verticalGap, min: 64, max: contentCanvas.y - 92)
        )
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        guard maximum >= minimum else { return (minimum + maximum) / 2 }
        return Swift.max(minimum, Swift.min(value, maximum))
    }
}

public struct StudyItem: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: StudyItemKind
    public var urlPath: String?
    public var isSample: Bool
    public var isNotebookNote: Bool

    public init(id: String, title: String, subtitle: String, kind: StudyItemKind, urlPath: String?, isSample: Bool, isNotebookNote: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.urlPath = urlPath
        self.isSample = isSample
        self.isNotebookNote = isNotebookNote
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case kind
        case urlPath
        case isSample
        case isNotebookNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        kind = try container.decode(StudyItemKind.self, forKey: .kind)
        urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath)
        isSample = try container.decode(Bool.self, forKey: .isSample)
        isNotebookNote = try container.decodeIfPresent(Bool.self, forKey: .isNotebookNote) ?? false
    }

    public var url: URL? {
        urlPath.map { URL(fileURLWithPath: $0) }
    }

    public var isImportedMarkdownFile: Bool {
        !isSample && kind == .markdown && url != nil
    }

    public var editsBackingMarkdownFile: Bool {
        isImportedMarkdownFile && isNotebookNote
    }

    public var canBecomeNotebookNote: Bool {
        isImportedMarkdownFile && !isNotebookNote
    }
}

public enum AgentRole: String, Codable {
    case user
    case assistant
}

public struct AgentMessage: Identifiable, Codable, Hashable {
    public var id: UUID
    public var role: AgentRole
    public var text: String
    public var source: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), role: AgentRole, text: String, source: String?, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }

    public var isUsableAgentAnswer: Bool {
        role == .assistant
            && !text.hasPrefix("未配置密钥")
            && !text.hasPrefix("未配置 OPENAI_API_KEY")
            && !text.hasPrefix("No key is configured")
            && !text.hasPrefix("请求失败：")
            && !text.hasPrefix("Agent 请求失败：")
            && !text.hasPrefix("Request failed:")
    }
}

public struct PersistedWorkspace: Codable {
    public var importedItems: [StudyItem]
    public var notesByItemID: [String: String]
    public var selectedItemID: String?
    public var activeNotebookItemID: String?
    public var modelName: String?
    public var workspaceLayout: WorkspaceLayout?
    public var threePaneOrder: [WorkspacePaneRole]?
    public var agentSurface: AgentSurface?
    public var noteRenderMode: NoteRenderMode?
    public var showLibrary: Bool?
    public var showReader: Bool?
    public var showAgent: Bool?
    public var showNotes: Bool?
    public var showRightPane: Bool?
    public var showDailyInspiration: Bool?
    public var appearanceModeRaw: String?
    public var adaptImportedDocumentColors: Bool?
    public var interfaceLanguageRaw: String?

    public init(importedItems: [StudyItem] = [], notesByItemID: [String: String] = [:], selectedItemID: String? = nil, activeNotebookItemID: String? = nil, modelName: String? = nil, workspaceLayout: WorkspaceLayout? = nil, threePaneOrder: [WorkspacePaneRole]? = nil, agentSurface: AgentSurface? = nil, noteRenderMode: NoteRenderMode? = nil, showLibrary: Bool? = nil, showReader: Bool? = nil, showAgent: Bool? = nil, showNotes: Bool? = nil, showRightPane: Bool? = nil, showDailyInspiration: Bool? = nil, appearanceModeRaw: String? = nil, adaptImportedDocumentColors: Bool? = nil, interfaceLanguageRaw: String? = nil) {
        self.importedItems = importedItems
        self.notesByItemID = notesByItemID
        self.selectedItemID = selectedItemID
        self.activeNotebookItemID = activeNotebookItemID
        self.modelName = modelName
        self.workspaceLayout = workspaceLayout
        self.threePaneOrder = threePaneOrder
        self.agentSurface = agentSurface
        self.noteRenderMode = noteRenderMode
        self.showLibrary = showLibrary
        self.showReader = showReader
        self.showAgent = showAgent
        self.showNotes = showNotes
        self.showRightPane = showRightPane
        self.showDailyInspiration = showDailyInspiration
        self.appearanceModeRaw = appearanceModeRaw
        self.adaptImportedDocumentColors = adaptImportedDocumentColors
        self.interfaceLanguageRaw = interfaceLanguageRaw
    }
}

public struct QuietInsight: Hashable {
    public var body: String
    public var noteBlock: String

    public init(body: String, noteBlock: String) {
        self.body = body
        self.noteBlock = noteBlock
    }

    public static func agent(materialTitle: String, answer: String, language: WeiBeiInterfaceLanguage = .chinese) -> QuietInsight? {
        let body = String(answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(360))
        guard !body.isEmpty else { return nil }
        return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
    }

    public static func make(materialTitle: String, materialText: String, noteText: String, selectionText: String?, language: WeiBeiInterfaceLanguage = .chinese) -> QuietInsight {
        let hasMaterial = !materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let selection = selectionText?.trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty {
            let excerpt = short(selection, count: 54)
            if !noteText.contains(String(selection.prefix(18))) {
                let body = language.text("选区还没有进入笔记：\(excerpt)。先收为摘录，再补一句自己的判断。", "The selection is not in the note yet: \(excerpt). Save it as an excerpt, then add one sentence of your own judgment.")
                return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
            }
            let body = hasMaterial
                ? language.text("选区已经出现在笔记里。下一步更适合追问它和当前材料其他段落的关系。", "The selection is already in the note. Next, ask how it relates to other parts of the current material.")
                : language.text("选区已经出现在笔记里。下一步更适合追问这段话还能补哪条依据。", "The selection is already in the note. Next, ask what evidence could support this passage.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        let candidate = firstUsefulLine(in: materialText)
        guard !candidate.isEmpty else {
            let noteCandidate = firstUsefulLine(in: noteText)
            if !noteCandidate.isEmpty {
                let body = language.text("当前笔记有一条可以继续整理：\(short(noteCandidate, count: 58))。建议补来源或写成问题。", "The current note has a line worth organizing: \(short(noteCandidate, count: 58)). Add a source or turn it into a question.")
                return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
            }
            let body = language.text("当前没有可读材料。先导入或选择一份 HTML、PDF 或 Markdown。", "There is no readable material yet. Import or choose an HTML, PDF, or Markdown file first.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        if !noteText.contains(String(candidate.prefix(14))) {
            let body = language.text("当前材料有一条还没进入笔记：\(short(candidate, count: 58))。建议补到摘录区。", "The current material has a line not yet in the note: \(short(candidate, count: 58)). Add it to the excerpts.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        let body = language.text("当前笔记已经覆盖材料开头。建议检查是否写了来源、例子和待追问。", "The current note already covers the start of the material. Check whether it includes sources, examples, and follow-up questions.")
        return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
    }

    private static func noteBlock(body: String, source: String, language: WeiBeiInterfaceLanguage) -> String {
        """
        > [!note] \(language.text("阅读线索", "Reading clue"))
        >
        > \(body)
        >
        > \(language.text("来源", "Source"))：\(source)
        """
    }

    private static func firstUsefulLine(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .map(cleanMarkdownLine)
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "。！？.!?")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isUsefulCandidate) ?? ""
    }

    private static func cleanMarkdownLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.hasPrefix("```"), !line.hasPrefix("|") else { return "" }
        line = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: " ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^>\s*(?:\[[!][^\]]+\][+-]?\s*)?"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]\s+\[[ xX]\]\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]?\s*\d*\.?\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"[*_`~=#]"#, with: "", options: .regularExpression)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulCandidate(_ text: String) -> Bool {
        guard text.count >= 8, !text.contains("|") else { return false }
        let readableCount = text.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || (0x4E00...0x9FFF).contains($0.value)
        }.count
        return readableCount >= 6
    }

    private static func short(_ text: String, count: Int) -> String {
        text.count > count ? "\(text.prefix(count))..." : text
    }
}

public enum PageNavigator {
    public static func previous(_ index: Int) -> Int {
        max(index - 1, 0)
    }

    public static func next(_ index: Int, pageCount: Int) -> Int {
        min(index + 1, max(pageCount - 1, 0))
    }

    public static func display(_ index: Int, pageCount: Int) -> String {
        "\(min(index + 1, max(pageCount, 1))) / \(max(pageCount, 1))"
    }
}

public enum TopBarLeadingInset {
    public static func value(isFullScreen: Bool) -> Double {
        isFullScreen ? 12 : 80
    }
}

public enum PDFModeChipPresentation {
    public static func showsLabel(isExpanded: Bool) -> Bool {
        isExpanded
    }

    public static func fillOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.86 }
        return isHovering ? 0.78 : 0.66
    }

    public static func strokeOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.58 }
        return isHovering ? 0.34 : 0.18
    }

    public static func controlOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.94 }
        return isHovering ? 0.84 : 0.70
    }
}

public enum ReaderSearch {
    public static func cleaned(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func firstMatch(in text: String, query: String) -> NSRange? {
        let query = cleaned(query)
        guard !query.isEmpty else { return nil }
        let range = (text as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        return range.location == NSNotFound ? nil : range
    }
}

public enum LibraryNavigator {
    public static func adjacentID(in ids: [String], selectedID: String?, step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let selectedID, let index = ids.firstIndex(of: selectedID) else {
            return ids[0]
        }
        return ids[(index + step + ids.count) % ids.count]
    }
}
