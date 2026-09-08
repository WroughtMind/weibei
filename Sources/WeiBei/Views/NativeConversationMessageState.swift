import AppKit
import SwiftUI
import WeiBeiCore

/// Derived display data for one message in one conversation surface. No row views live here.
@MainActor
final class NativeConversationMessageState {
    private(set) var message: AgentMessage
    let renderer = NativeChatMarkdownView.Coordinator()
    let markdownMemo = AgentMessageMarkdownMemo()
    let imageHandler = MarkdownImageSchemeHandler()
    private(set) var version = 0
    private(set) var preparationCount = 0
    private(set) var citations: [AgentCitation] = []
    private(set) var sourcePresentation: AgentReplySourceInlinePresentation?
    private(set) var actionDrafts: [UUID: AgentReplyActionDraft] = [:]
    private var rawText: String
    var displayedText: String { rawText }
    private var submittedText: String?
    private var submittedLanguage: WeiBeiInterfaceLanguage?
    private var toggles: Set<Int> = []
    var onChange: (() -> Void)?
    var height: CGFloat = 60
    var bodyHeight: CGFloat = 20
    var measuredWidth: CGFloat?
    var measuredFontSize: CGFloat?
    var measuredVersion: Int?
    private var requestedWidth: CGFloat?
    private var requestedFontSize: CGFloat?
    var userNaturalWidth: CGFloat?

    func invalidateLayout(width: CGFloat, fontSize: CGFloat) -> CGFloat? {
        guard requestedWidth != width || requestedFontSize != fontSize else { return nil }
        let previousBody = bodyHeight
        if let oldWidth = requestedWidth, let oldFont = requestedFontSize {
            bodyHeight = max(fontSize * 1.5, bodyHeight * oldWidth / width * pow(fontSize / oldFont, 2))
        } else {
            bodyHeight = max(fontSize * 1.5, ceil(CGFloat(rawText.utf16.count) * fontSize * 0.75 / width) * fontSize * 1.6)
        }
        requestedWidth = width
        requestedFontSize = fontSize
        measuredWidth = nil
        measuredFontSize = nil
        measuredVersion = nil
        return max(1, ceil(bodyHeight + max(20, height - previousBody)))
    }

    init(message: AgentMessage) {
        self.message = message
        rawText = message.text
        renderer.managesReadingPosition = false
        renderer.pipeline.onApply = { [weak self] document, edit in
            guard let self else { return }
            self.renderer.apply(document, edit: edit)
            self.version &+= 1
            self.preparationCount += 1
            self.measuredVersion = nil
            self.onChange?()
        }
        renderer.onCalloutToggle = { [weak self] id in
            guard let self else { return }
            if !self.toggles.insert(id).inserted { self.toggles.remove(id) }
            self.submittedText = nil
            self.prepare()
        }
        updateDrafts()
    }

    func update(_ message: AgentMessage, displayedText: String) {
        let contentChanged = !rawText.utf16.elementsEqual(displayedText.utf16)
            || self.message.sources != message.sources || self.message.contentBlocks != message.contentBlocks
        self.message = message
        rawText = displayedText
        updateDrafts()
        if contentChanged {
            userNaturalWidth = nil
            submittedText = nil
            measuredVersion = nil
            // Previously prepared messages keep receiving content while their row is recycled.
            if preparationCount > 0 || renderer.view != nil { prepare() }
        }
    }

    func prepare() {
        let language = renderer.interfaceLanguage
        guard submittedText == nil || submittedLanguage != language else { return }
        let text = AgentNativeMessageContent.markdown(text: rawText, blocks: message.contentBlocks)
        sourcePresentation = AgentReplySourceInlinePresentation(text: text, sources: message.sources, language: language)
        citations = AgentCitationParser.parse(rawText).citations.filter {
            switch $0.kind {
            case .material, .note, .selection: return false
            case .learningMemory, .learningRecord: return message.origin?.courseID != nil
            case .session: return true
            }
        }
        let markdown = markdownMemo.outputs(text: text, sources: message.sources, language: language).finalized
        submittedText = markdown
        submittedLanguage = language
        renderer.pipeline.submit(.init(markdown: markdown, messageID: message.id,
            toggledCallouts: toggles, interfaceLanguage: language))
    }

    private func updateDrafts() {
        for action in message.actions where actionDrafts[action.id] == nil {
            actionDrafts[action.id] = AgentReplyActionDraft(action: action)
        }
        let ids = Set(message.actions.map(\.id))
        actionDrafts = actionDrafts.filter { ids.contains($0.key) }
    }

    func invalidate() {
        renderer.pipeline.invalidate()
        renderer.view = nil
        imageHandler.invalidate()
        onChange = nil
    }
}
