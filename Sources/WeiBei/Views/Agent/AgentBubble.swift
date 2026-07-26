import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct AgentBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    var message: AgentMessage
    @State private var hovering = false

    var body: some View {
        Group {
            if isUser {
                userTurn
            } else {
                assistantTurn
            }
        }
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
    }

    @ViewBuilder
    private var userTurn: some View {
        // Quiet paper chip on the right edge: role is encoded by position + surface,
        // so no "你" label, no accent rail, no messenger chrome.
        // Long material/section source strings are intentionally not shown — they clutter
        // the turn without helping the learner (navigation lives in tags / reader).
        VStack(alignment: .trailing, spacing: 4) {
            AgentMessageMarkdownText(
                text: message.text,
                rendersRichMarkdown: false
            )
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(userBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(userBubbleStroke, lineWidth: 1)
                    }
                    .shadow(
                        color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.0 : (hovering ? 0.06 : 0.04)),
                        radius: hovering ? 6 : 4,
                        y: hovering ? 2 : 1.2
                    )
            }
            .frame(maxWidth: 520, alignment: .trailing)
        }
        .weibeiHoverLift(active: hovering, amount: 0.6)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var userBubbleFill: Color {
        // Same paper family as chips/panels: a slightly raised slip of paper, not a tinted chat blob.
        store.appearanceMode.isDark
            ? WeiBeiTheme.paperRaised.opacity(hovering ? 0.58 : 0.46)
            : WeiBeiTheme.paperRaised.opacity(hovering ? 1.0 : 0.96)
    }

    private var userBubbleStroke: Color {
        store.appearanceMode.isDark
            ? WeiBeiTheme.hairline.opacity(hovering ? 0.58 : 0.42)
            : WeiBeiTheme.hairline.opacity(hovering ? 0.52 : 0.38)
    }

    @ViewBuilder
    private var assistantTurn: some View {
        if isCredentialNotice {
            credentialNoticeContent
                .padding(.vertical, 8)
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(WeiBeiTheme.link.opacity(hovering ? 0.50 : 0.34))
                        .frame(width: 2, height: 30)
                }
        } else {
            regularMessageContent
                .padding(.vertical, 10)
                .padding(.leading, hasRenderableRichAnswer ? 0 : 20)
                .padding(.trailing, hasRenderableRichAnswer ? 0 : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Assistant messages no longer carry a cinnabar leading mark;
                // only credential notices keep a link-blue affordance.
        }
    }

    private var regularMessageContent: some View {
        let citationParse = AgentCitationParser.parse(message.text)
        return VStack(alignment: .leading, spacing: 8) {
            messageMetadata

            if let richAnswer = message.richAnswer,
               richAnswer.mode == .rich,
               !richAnswer.scenes.isEmpty {
                richAnswerFlow(richAnswer)
            } else {
                // Hang-proof agent chat: finalized turns use KaTeX with frozen height;
                // failures stay native text (no WebView). Never height→scroll.
                AgentMessageMarkdownText(
                    text: citationParse.displayText,
                    rendersRichMarkdown: true,
                    usesFinalizedKaTeX: !isFailureMessage,
                    messageID: message.id
                )
            }

            if !citationParse.citations.isEmpty {
                AgentCitationTagRow(citations: citationParse.citations) { citation in
                    activateCitation(citation)
                }
            }

            if isFailureMessage {
                HStack(spacing: 6) {
                    if store.canRetryLastFailedAgentRequest {
                        Button(store.ui("重试", "Retry")) {
                            store.retryLastFailedAgentRequest()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                    Button(store.ui("回填问题", "Restore question")) {
                        if let question = store.lastFailedAgentQuestion, !question.isEmpty {
                            store.agentDraft = question
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                .padding(.top, 2)
            } else if message.id == store.lastUsableAgentAnswerID {
                if let update = store.latestAgentLearningUpdate,
                   !update.entries.isEmpty || !update.resolutions.isEmpty || !update.suggestedNext.isEmpty {
                    learningUpdateContent(update)
                }
                if let proposal = store.latestAgentNoteProposal, !proposal.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.ui("依据", "Evidence"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                        ForEach(Array(proposal.evidence.enumerated()), id: \.offset) { _, evidence in
                            Text("• \(evidence)")
                                .font(.caption)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 6) {
                    if store.selectionContext != nil {
                        Button(store.ui("摘录", "Excerpt")) {
                            store.appendSelectionToNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    Button(store.agentWriteActionTitle) {
                        store.applyLastAgentAnswerToNote()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换", "Replace")) {
                            store.replaceSelectionWithLastAgentAnswer()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func richAnswerFlow(_ presentation: RichAnswerPresentation) -> some View {
        ForEach(Array(presentation.resolvedParts.enumerated()), id: \.offset) { index, part in
            switch part.kind {
            case .narrative:
                if let text = part.text, !text.isEmpty {
                    RichAnswerNarrativeText(text: text)
                        .frame(
                            maxWidth: AgentChatLayoutMetrics.isWide(layout: store.layout)
                                ? AgentChatLayoutMetrics.wideMaxWidth
                                : AgentChatLayoutMetrics.compactMaxWidth,
                            alignment: .leading
                        )
                }
            case .scene:
                if let sceneID = part.sceneID,
                   let scopedPresentation = scopedRichAnswer(presentation, sceneID: sceneID) {
                    RichAnswerHost(
                        presentation: scopedPresentation,
                        onOpenEvidence: openRichAnswerEvidence,
                        onOpenAsset: openRichAnswerAsset,
                        assetPreview: richAnswerAssetPreview,
                        onAction: submitRichAnswerAction
                    )
                    .id("rich-answer-\(message.id.uuidString)-\(sceneID)-\(index)")
                    .frame(
                        maxWidth: AgentChatLayoutMetrics.isWide(layout: store.layout)
                            ? AgentChatLayoutMetrics.wideMaxWidth
                            : AgentChatLayoutMetrics.compactMaxWidth,
                        alignment: .leading
                    )
                }
            }
        }
    }

    private func scopedRichAnswer(
        _ presentation: RichAnswerPresentation,
        sceneID: String
    ) -> RichAnswerPresentation? {
        guard let scene = presentation.scenes.first(where: { $0.id == sceneID }) else { return nil }
        var scoped = presentation
        scoped.scenes = [scene]
        scoped.parts = nil
        let evidenceIDs = Set(scene.evidenceIDs)
        scoped.evidenceLedger = presentation.evidenceLedger.filter { evidenceIDs.contains($0.id) }
        return scoped
    }

    private func submitRichAnswerAction(_ prompt: String) {
        guard !store.isAskingAgent else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.agentDraft = trimmed
        store.askAgent()
    }

    private func learningUpdateContent(_ update: StudyAgentLearningUpdate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(store.ui("本轮记住", "Remembered This Turn"), systemImage: "brain.head.profile")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)

            ForEach(Array(update.entries.prefix(4).enumerated()), id: \.offset) { _, entry in
                Text("\(memoryKindLabel(entry.kind))：\(entry.text)")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(update.resolutions.prefix(4).enumerated()), id: \.offset) { _, resolution in
                let isResolved = store.isLearningMemoryResolved(resolution.memoryID)
                HStack(alignment: .top, spacing: 6) {
                    Text(store.ui("建议结案：\(resolution.text)", "Suggested resolution: \(resolution.text)"))
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        if isResolved {
                            store.restoreLearningMemoryResolution(resolution)
                        } else {
                            store.confirmLearningMemoryResolution(resolution)
                        }
                    } label: {
                        Image(systemName: isResolved ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(active: isResolved, size: 22))
                    .help(store.ui(isResolved ? "撤销结案" : "确认结案", isResolved ? "Undo resolution" : "Confirm resolution"))
                }
            }

            ForEach(Array(update.suggestedNext.prefix(3).enumerated()), id: \.offset) { _, next in
                Text("→ \(next)")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.link)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 9)
        .padding(.vertical, 5)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.72))
                .frame(width: 1)
        }
    }

    private func memoryKindLabel(_ kind: LearningMemoryKind) -> String {
        switch kind {
        case .goal:
            return store.ui("目标", "Goal")
        case .understood:
            return store.ui("已理解", "Understood")
        case .confusion:
            return store.ui("困惑", "Confusion")
        case .nextStep:
            return store.ui("下一步", "Next Step")
        case .preference:
            return store.ui("偏好", "Preference")
        }
    }

    private var messageMetadata: some View {
        HStack(spacing: 6) {
            Text("WeiBei")
                .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
            if let backend = message.backend {
                Text(backendLabel(backend))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            // Do not render message.source here — long "课程 HTML，章节标识…" strings
            // add noise; materials / learning context use citation tags instead.
            Spacer(minLength: 0)
        }
    }

    private func activateCitation(_ citation: AgentCitation) {
        switch citation.kind {
        case .material:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "material", value: citation.value)
            }
        case .note:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "note", value: citation.value)
            }
        case .selection:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "selection", value: citation.value)
            }
        case .learningRecord:
            withAnimation(WeiBeiMotion.panel) {
                store.resumePreviousStudy()
            }
        case .learningMemory:
            withAnimation(WeiBeiMotion.panel) {
                store.presentCourseWorkspace(.sessions)
            }
        case .session:
            break
        }
    }

    private var credentialNoticeContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.ui("需要设置密钥", "Key Required"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text(displayText)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .allowsHitTesting(false)
        }
    }

    private func openRichAnswerEvidence(_ evidence: RichAnswerEvidence) {
        var label = evidence.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.hasPrefix("["), label.hasSuffix("]"), label.count > 2 {
            label = String(label.dropFirst().dropLast())
        }
        for prefix in ["材料：", "笔记：", "选区："] where label.hasPrefix(prefix) {
            label = String(label.dropFirst(prefix.count))
            break
        }
        guard !label.isEmpty else { return }
        store.openSourceReference("来源：\(label)")
    }

    private func openRichAnswerAsset(_ assetID: String) {
        withAnimation(WeiBeiMotion.panel) {
            store.select(itemID: assetID)
        }
    }

    private func richAnswerAssetPreview(_ assetID: String) -> NSImage? {
        guard let item = store.item(withID: assetID), let url = item.url else { return nil }
        if item.kind == .pdf,
           let page = PDFDocument(url: url)?.page(at: 0) {
            return page.thumbnail(of: NSSize(width: 1200, height: 1500), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var hasRenderableRichAnswer: Bool {
        message.richAnswer?.mode == .rich && message.richAnswer?.scenes.isEmpty == false
    }

    private var isCredentialNotice: Bool {
        message.role == .assistant
            && (message.text.hasPrefix("未配置密钥") || message.text.hasPrefix("未配置 OPENAI_API_KEY") || message.text.hasPrefix("No key is configured"))
    }

    private var isFailureMessage: Bool {
        message.role == .assistant && WorkspaceStore.isAgentFailureMessage(message.text)
    }

    private var displayText: String {
        guard isCredentialNotice else { return message.text }
        if isOfflineContextPreview {
            return message.text
        }
        let scope = store.hasSelectionAttachments ? store.ui("\(store.agentPromptScope)、已选文本片段", "\(store.agentPromptScope) and selected text fragments") : store.agentPromptScope
        return store.ui("设置后会结合\(scope)作答；未配置时不会编造内容。", "After setup, answers will use \(scope). Without a key, WeiBei will not invent content.")
    }

    private var isOfflineContextPreview: Bool {
        message.text.contains("## 离线草稿")
            || message.text.contains("## Offline Draft")
    }

    private func backendLabel(_ backend: StudyAgentBackend) -> String {
        switch backend {
        case .pi: return "PI"
        case .openAI: return "API"
        case .offline: return store.ui("离线", "Offline")
        }
    }
}

struct RichAnswerNarrativeText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case let .heading(level):
                    Text(attributed(block.text))
                        .font(.system(size: level <= 2 ? 21 : 17, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph:
                    Text(attributed(block.text))
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                        Text(attributed(block.text))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(WeiBeiTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .quote:
                    Text(attributed(block.text))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(WeiBeiTheme.hairline.opacity(0.72))
                                .frame(width: 1)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(Block(kind: .paragraph, text: paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if isStandaloneSourceReference(line) {
                flushParagraph()
                continue
            }
            let headingMarkers = line.prefix { $0 == "#" }.count
            if headingMarkers > 0, headingMarkers <= 6, line.dropFirst(headingMarkers).first == " " {
                flushParagraph()
                result.append(
                    Block(
                        kind: .heading(level: headingMarkers),
                        text: String(line.dropFirst(headingMarkers)).trimmingCharacters(in: .whitespaces)
                    )
                )
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                result.append(Block(kind: .bullet, text: String(line.dropFirst(2))))
                continue
            }
            if line.hasPrefix("> ") {
                flushParagraph()
                result.append(Block(kind: .quote, text: String(line.dropFirst(2))))
                continue
            }
            paragraphLines.append(line)
        }
        flushParagraph()
        return result
    }

    private func isStandaloneSourceReference(_ line: String) -> Bool {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return false }
        return ["[材料：", "[笔记：", "[选区："].contains { line.hasPrefix($0) }
    }

    private func attributed(_ value: String) -> AttributedString {
        let displayValue = RichAnswerDisplayText.normalizedInlineMath(value)
        return (try? AttributedString(markdown: displayValue)) ?? AttributedString(displayValue)
    }

    private struct Block {
        enum Kind {
            case heading(level: Int)
            case paragraph
            case bullet
            case quote
        }

        let kind: Kind
        let text: String
    }
}

enum AgentFinalizedMarkdownHeightCache {
    private static let lock = NSLock()
    private static var values: [String: CGFloat] = [:]

    static func height(for key: String) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    static func store(_ height: CGFloat, for key: String) {
        guard height > 44 else { return }
        lock.lock(); defer { lock.unlock() }
        if let existing = values[key], abs(existing - height) < 2 { return }
        values[key] = height
    }

    static func cacheKey(messageID: UUID?, text: String, widthBucket: Int) -> String {
        let id = messageID?.uuidString ?? "anon"
        let prefix = text.prefix(64)
        return "\(id):\(text.count):\(prefix):w\(widthBucket)"
    }

    static func widthBucket(_ width: CGFloat) -> Int {
        max(Int((width / 24.0).rounded(.down)) * 24, 0)
    }
}

struct AgentChatLayoutWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var agentChatLayoutWidth: CGFloat {
        get { self[AgentChatLayoutWidthKey.self] }
        set { self[AgentChatLayoutWidthKey.self] = newValue }
    }
}

/// Agent chat markdown — shared by immersive conversation and selection float.
/// - Finalized assistant turns: hang-proof KaTeX via `MarkdownPreviewView` with width-aware height.
/// - Streaming / user / failures / no-math: native `AttributedString`.
struct AgentMessageMarkdownText: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.agentChatLayoutWidth) private var layoutWidth
    var text: String
    var rendersRichMarkdown: Bool
    /// Selection-float / narrow surfaces: smaller type, still fills available width.
    var compact: Bool = false
    /// Completed assistant turns only — never streaming, user, or failure bubbles.
    var usesFinalizedKaTeX: Bool = false
    var messageID: UUID? = nil

    private var katexMarkdown: String {
        AgentChatKaTeXMarkdown.prepare(text)
    }

    private var widthBucket: Int {
        AgentFinalizedMarkdownHeightCache.widthBucket(layoutWidth)
    }

    private var shouldUseKaTeX: Bool {
        usesFinalizedKaTeX
            && rendersRichMarkdown
            && AgentChatKaTeXMarkdown.containsRecognizableMath(katexMarkdown)
    }

    var body: some View {
        Group {
            if shouldUseKaTeX {
                finalizedKaTeXBody
            } else {
                nativeBody
            }
        }
        .modifier(AgentMessageTextWidthModifier(fillsReadingColumn: rendersRichMarkdown || compact))
    }

    private var cacheKey: String {
        AgentFinalizedMarkdownHeightCache.cacheKey(
            messageID: messageID,
            text: katexMarkdown,
            widthBucket: widthBucket
        )
    }

    @ViewBuilder
    private var finalizedKaTeXBody: some View {
        // Hang-proof KaTeX: compact preview forwards wheel to the conversation ScrollView.
        // Height freezes per width-bucket; resize changes the bucket and remasures.
        // NEVER wire onContentHeightChange to scrollAgentToBottom.
        MarkdownPreviewView(
            markdown: katexMarkdown,
            markdownBaseURL: store.currentMarkdownBaseURL,
            appearanceMode: store.appearanceMode,
            interfaceLanguage: store.interfaceLanguage,
            compact: true,
            fitsContentHeight: true,
            freezeHeightAfterMeasure: true,
            seedContentHeight: AgentFinalizedMarkdownHeightCache.height(for: cacheKey),
            layoutWidthBucket: widthBucket,
            onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
            onSourceReference: { reference in store.openSourceReference(reference) },
            onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
            onMeasuredHeight: { height in
                AgentFinalizedMarkdownHeightCache.store(height, for: cacheKey)
            }
        )
        .id("\(messageID?.uuidString ?? "msg")-\(widthBucket)")
    }

    private var nativeBody: some View {
        Text(renderedText)
            .font(.system(size: compact ? 13.2 : (rendersRichMarkdown ? 15 : 14.5)))
            .lineSpacing(compact ? 4.2 : (rendersRichMarkdown ? 5.5 : 4.5))
            .foregroundStyle(WeiBeiTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var renderedText: AttributedString {
        // Streaming / no-math path: Unicode math readability without WKWebView.
        let display = RichAnswerDisplayText.normalizedInlineMath(text)
        return (try? AttributedString(markdown: display)) ?? AttributedString(display)
    }
}

struct AgentMessageTextWidthModifier: ViewModifier {
    let fillsReadingColumn: Bool

    func body(content: Content) -> some View {
        if fillsReadingColumn {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Hug text width (wraps within the bubble's maxWidth: 520), not a full-width bar.
            content
        }
    }
}

/// Product loading motion — 「行文进行中 V3」.
/// Driven solely by `store.agentActivityText` (no demo status carousel).
///
/// Hang-proof: motion runs in a fixed-size `NSView` + `CADisplayLink` that only
/// `setNeedsDisplay()`. It never enters SwiftUI `TimelineView`, so parent
/// `ScrollView` / `LazyVStack` do not re-run `sizeThatFits` every frame
/// (that thrash was freezing the app after a couple of scrolls).
///
/// Geometry: cinnabar orbit keeps equal padding on all four sides of the status text.
///
/// Model (view coords, flipped):
/// ```
/// ┌──────── path (stroke centerline) ────────┐
/// │  pad                                     │
/// │     ┌──── glyph / line box ────┐         │
/// │ pad │  加载词                  │ pad     │
/// │     └──────────────────────────┘         │
/// │  pad                                     │
/// └──────────────────────────────────────────┘
/// ```
/// `orbitPadding` is the clear gap from the line-box edge to the stroke *centerline*
/// on every side. Half the stroke width sits outside that centerline, so the view
/// grows by `lineWidth` total to avoid clipping.
struct AgentStreamingResponse: View {
    @EnvironmentObject private var store: WorkspaceStore
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("WeiBei")
                    .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
                Text("PI")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            // Streaming stays native + throttled — KaTeX only after the turn finalizes.
            AgentStreamingMarkdownText(text: text, compact: false)
        }
        .padding(.vertical, 10)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(store.ui("PI 正在回答", "PI is responding")))
    }
}

/// Throttled native markdown for in-flight tokens (avoids per-token AttributedString thrash).
struct AgentStreamingMarkdownText: View {
    var text: String
    var compact: Bool = false
    @State private var displayedText = ""
    @State private var flushTask: Task<Void, Never>?

    var body: some View {
        AgentMessageMarkdownText(
            text: displayedText.isEmpty ? text : displayedText,
            rendersRichMarkdown: true,
            compact: compact,
            usesFinalizedKaTeX: false
        )
        .onAppear {
            displayedText = text
        }
        .onChange(of: text) { _, newValue in
            flushTask?.cancel()
            flushTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard !Task.isCancelled else { return }
                displayedText = newValue
            }
        }
        .onDisappear {
            flushTask?.cancel()
        }
    }
}
