import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

// MARK: - Agent citation tags (materials / learning / selection)

/// Bracket citations Pi emits in answers, e.g. `[材料：…]`, `[学习记录：上次位置]`.
enum AgentCitationKind: String, Equatable {
    case material
    case note
    case selection
    case learningRecord
    case learningMemory
    case session

    var systemImage: String {
        switch self {
        case .material: return "doc.text"
        case .note: return "note.text"
        case .selection: return "text.quote"
        case .learningRecord: return "bookmark"
        case .learningMemory: return "brain.head.profile"
        case .session: return "bubble.left.and.bubble.right"
        }
    }

    func shortLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .material: return language.text("材料", "Material")
        case .note: return language.text("笔记", "Note")
        case .selection: return language.text("选区", "Selection")
        case .learningRecord: return language.text("学习记录", "Study record")
        case .learningMemory: return language.text("学习记忆", "Memory")
        case .session: return language.text("会话", "Session")
        }
    }
}

struct AgentCitation: Identifiable, Equatable {
    let id: String
    let kind: AgentCitationKind
    let raw: String
    let value: String

    var displayTitle: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.rawValue : trimmed
    }
}

enum AgentCitationParser {
    /// Matches `[材料：…]` / `[学习记录：上次位置]` style Pi citation labels.
    private static let pattern = #"\[(材料|笔记|选区|学习记录|学习记忆|会话)[：:]\s*([^\]\n]{1,300})\]"#

    static func parse(_ text: String) -> (displayText: String, citations: [AgentCitation]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var citations: [AgentCitation] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let kindRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { return }
            let kindToken = String(text[kindRange])
            let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = String(text[fullRange])
            guard let kind = kind(from: kindToken) else { return }
            let key = "\(kind.rawValue)|\(value)"
            guard seen.insert(key).inserted else { return }
            citations.append(
                AgentCitation(
                    id: key,
                    kind: kind,
                    raw: raw,
                    value: value
                )
            )
        }
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: "")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? text : cleaned, citations)
    }

    private static func kind(from token: String) -> AgentCitationKind? {
        switch token {
        case "材料": return .material
        case "笔记": return .note
        case "选区": return .selection
        case "学习记录": return .learningRecord
        case "学习记忆": return .learningMemory
        case "会话": return .session
        default: return nil
        }
    }
}

struct AgentCitationTagRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citations: [AgentCitation]
    var onActivate: (AgentCitation) -> Void

    var body: some View {
        // Wrapping HStack via LazyVGrid-like flow using flexible chips.
        FlexibleCitationWrap(citations: citations, onActivate: onActivate)
    }
}

/// Simple left-to-right wrap without GeometryReader thrash on the chat LazyVStack.
struct FlexibleCitationWrap: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citations: [AgentCitation]
    var onActivate: (AgentCitation) -> Void

    var body: some View {
        // Single horizontal wrap via ViewThatFits-style chunking is heavy; use a
        // multi-line HStack of lines built greedily at layout time via Preference-free
        // fixed wrapping: put chips in a wrapping layout using `HStack` + multiple rows
        // computed by character budget.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chunkedRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { citation in
                        AgentCitationTag(citation: citation) {
                            onActivate(citation)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var chunkedRows: [[AgentCitation]] {
        var rows: [[AgentCitation]] = []
        var current: [AgentCitation] = []
        var budget: CGFloat = 0
        let rowBudget: CGFloat = 52 // approx character units per row
        for citation in citations {
            let cost = CGFloat(min(citation.displayTitle.count + 6, 28))
            if !current.isEmpty, budget + cost > rowBudget {
                rows.append(current)
                current = []
                budget = 0
            }
            current.append(citation)
            budget += cost
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

struct AgentCitationTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citation: AgentCitation
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: citation.kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(chipLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) { self.hovering = hovering }
        }
        .accessibilityLabel(Text(helpText))
    }

    private var chipLabel: String {
        let kindLabel = citation.kind.shortLabel(language: store.interfaceLanguage)
        switch citation.kind {
        case .learningRecord, .learningMemory, .session:
            // Value is already a short kind phrase ("上次位置").
            return "\(kindLabel) · \(citation.displayTitle)"
        case .material, .note, .selection:
            let short = citation.displayTitle.count > 18
                ? String(citation.displayTitle.prefix(16)) + "…"
                : citation.displayTitle
            return "\(kindLabel) · \(short)"
        }
    }

    private var helpText: String {
        switch citation.kind {
        case .material:
            return store.ui("打开材料：\(citation.displayTitle)", "Open material: \(citation.displayTitle)")
        case .note:
            return store.ui("打开笔记：\(citation.displayTitle)", "Open note: \(citation.displayTitle)")
        case .selection:
            return store.ui("查看选区：\(citation.displayTitle)", "Open selection: \(citation.displayTitle)")
        case .learningRecord:
            return store.ui("回到上次学习位置", "Resume last study location")
        case .learningMemory:
            return store.ui("查看学习记忆", "Open study memory")
        case .session:
            return store.ui("当前会话", "Current session")
        }
    }

    private var foreground: Color {
        switch citation.kind {
        case .material:
            return hovering ? WeiBeiTheme.moss : WeiBeiTheme.moss.opacity(0.92)
        case .note:
            return hovering ? WeiBeiTheme.link : WeiBeiTheme.link.opacity(0.90)
        case .selection:
            return hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.cinnabar.opacity(0.88)
        case .learningRecord:
            return hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
        case .learningMemory:
            return hovering ? WeiBeiTheme.secondaryInk : WeiBeiTheme.tertiaryInk
        case .session:
            return WeiBeiTheme.tertiaryInk
        }
    }

    private var background: Color {
        switch citation.kind {
        case .material:
            return WeiBeiTheme.moss.opacity(hovering ? 0.14 : 0.09)
        case .note:
            return WeiBeiTheme.link.opacity(hovering ? 0.12 : 0.07)
        case .selection:
            return WeiBeiTheme.cinnabarSoft.opacity(hovering ? 0.55 : 0.38)
        case .learningRecord:
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.55 : 0.38)
        case .learningMemory:
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.42 : 0.28)
        case .session:
            return WeiBeiTheme.paperInset.opacity(0.22)
        }
    }

    private var border: Color {
        switch citation.kind {
        case .material:
            return WeiBeiTheme.moss.opacity(hovering ? 0.34 : 0.20)
        case .note:
            return WeiBeiTheme.link.opacity(hovering ? 0.32 : 0.18)
        case .selection:
            return WeiBeiTheme.cinnabar.opacity(hovering ? 0.36 : 0.22)
        case .learningRecord, .learningMemory, .session:
            return WeiBeiTheme.hairline.opacity(hovering ? 0.55 : 0.36)
        }
    }
}

/// Session-scoped height cache for finalized agent KaTeX rows.
/// Key includes a width bucket so resize can remeasure without thrash.
