import AppKit
import CoreText
import Foundation
import WeiBeiCore

/**
 * 验证产品资源和空工作区素材契约。
 */
enum ProductResourceSelfChecks {
    /**
     * 执行该领域的自检。
     */
    static func run(repositoryURL: URL) throws {
        expect(EmptyWorkspaceDayPeriod(hour: 5) == .morning
            && EmptyWorkspaceDayPeriod(hour: 10) == .morning
            && EmptyWorkspaceDayPeriod(hour: 11) == .midday
            && EmptyWorkspaceDayPeriod(hour: 16) == .midday
            && EmptyWorkspaceDayPeriod(hour: 17) == .evening
            && EmptyWorkspaceDayPeriod(hour: 22) == .evening
            && EmptyWorkspaceDayPeriod(hour: 23) == .lateNight
            && EmptyWorkspaceDayPeriod(hour: 4) == .lateNight, "empty workspace greeting follows morning, midday, evening, and late-night boundaries")
        expect(EmptyWorkspaceDayPeriod.morning.greeting(language: .chinese).contains("早安")
            && EmptyWorkspaceDayPeriod.midday.greeting(language: .chinese).contains("午安")
            && EmptyWorkspaceDayPeriod.evening.greeting(language: .chinese).contains("晚安")
            && EmptyWorkspaceDayPeriod.lateNight.greeting(language: .chinese).contains("夜深")
            && !EmptyWorkspaceDayPeriod.morning.greeting(language: .english).isEmpty, "empty workspace greetings stay localized and non-empty")

        let inspirationItems = EmptyWorkspaceInspirationCatalog.items
        expect(inspirationItems.count >= 6
            && EmptyWorkspaceInspirationCatalog.validationErrors.isEmpty
            && inspirationItems.contains(where: { if case .calligraphy = $0.presentation { return true }; return false })
            && inspirationItems.contains(where: { $0.presentation == .quotation })
            && inspirationItems.contains(where: { $0.presentation == .formula }), "daily inspiration catalog contains validated calligraphy, original-language quotation, and formulas")
        expect(inspirationItems.allSatisfy { item in
            !item.text.isEmpty
                && !item.credit.isEmpty
                && item.sourceURL?.scheme == "https"
                && !item.rightsLabel.isEmpty
                && item.rightsURL?.scheme == "https"
        }, "every daily inspiration keeps text, author/work credit, a reliable source, and rights metadata")
        var inspirationCalendar = Calendar(identifier: .gregorian)
        inspirationCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let inspirationDayOne = inspirationCalendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
        let inspirationDayTwo = inspirationCalendar.date(byAdding: .day, value: 1, to: inspirationDayOne)!
        expect(EmptyWorkspaceInspirationCatalog.item(for: inspirationDayOne, calendar: inspirationCalendar).id
            != EmptyWorkspaceInspirationCatalog.item(for: inspirationDayTwo, calendar: inspirationCalendar).id, "daily inspiration rotates deterministically from one local day to the next")

        let offlineChinesePreview = AgentOfflinePreview.render(
            AgentOfflinePreviewInput(
                language: .chinese,
                question: "解释利率为什么是资金价格",
                hasMaterial: true,
                materialTitle: "Mishkin 教材样例",
                materialText: "利率是资金使用价格的表达。金融市场通过利率配置资源。",
                noteTitle: "货币金融学课程 HTML",
                noteText: "## 摘录\n来源：Mishkin 教材样例",
                selectionTitle: "已选文本片段",
                selectionText: "利率是资金使用价格的表达。"
            )
        )
        expect(offlineChinesePreview.contains("## 离线草稿")
            && !offlineChinesePreview.hasPrefix("未配置密钥")
            && offlineChinesePreview.contains("未配置密钥；这里只整理当前可见内容")
            && offlineChinesePreview.contains("**问题**：解释利率为什么是资金价格")
            && offlineChinesePreview.contains("**上下文**：资料：Mishkin 教材样例 · 笔记：货币金融学课程 HTML · 选区：已选文本片段")
            && offlineChinesePreview.contains("## 可确认")
            && offlineChinesePreview.contains("- 选区依据：利率是资金使用价格的表达。")
            && offlineChinesePreview.contains("- 资料依据：利率是资金使用价格的表达。金融市场通过利率配置资源。")
            && offlineChinesePreview.contains("- 笔记线索：## 摘录 来源：Mishkin 教材样例")
            && offlineChinesePreview.contains("## 建议写入")
            && offlineChinesePreview.contains("- 把可确认依据写入笔记，并保留来源。")
            && !offlineChinesePreview.contains("| 上下文 | 内容 |")
            && !offlineChinesePreview.contains("> 资料摘录："), "offline agent draft stays compact, source-grounded, and note-ready without API key")

        let offlineEnglishPreview = AgentOfflinePreview.render(
            AgentOfflinePreviewInput(
                language: .english,
                question: "Explain the selected sentence",
                hasMaterial: false,
                materialTitle: "No document",
                materialText: "",
                noteTitle: "Current note",
                noteText: "",
                selectionTitle: nil,
                selectionText: nil
            )
        )
        expect(offlineEnglishPreview.contains("## Offline Draft")
            && !offlineEnglishPreview.hasPrefix("No key is configured")
            && offlineEnglishPreview.contains("No key is configured; this only organizes visible context")
            && offlineEnglishPreview.contains("**Question**: Explain the selected sentence")
            && offlineEnglishPreview.contains("**Context**: Material: None · Note: Current note · Selection: None")
            && offlineEnglishPreview.contains("## Confirmed")
            && offlineEnglishPreview.contains("- Note state: the current note is empty.")
            && offlineEnglishPreview.contains("## Suggested Note")
            && offlineEnglishPreview.contains("- Write the confirmed evidence into the note and keep the source attached.")
            && !offlineEnglishPreview.contains("| Context | Content |")
            && !offlineEnglishPreview.contains("> Note excerpt:"), "offline agent draft renders compact English empty-context state as Markdown")
        expect(AgentOfflinePreview.preview("A\nB\tC", limit: 20) == "A B C", "offline agent preview normalizes whitespace")
        let offlineSuggestedNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: offlineChinesePreview, language: .chinese) ?? ""
        expect(offlineSuggestedNoteBlock.contains("## 整理建议")
            && offlineSuggestedNoteBlock.contains("把可确认依据写入笔记，并保留来源。")
            && !offlineSuggestedNoteBlock.contains("## 离线草稿")
            && !offlineSuggestedNoteBlock.contains("## 可确认")
            && !offlineSuggestedNoteBlock.contains("**上下文**"), "writing an offline answer into notes keeps only the note-ready suggestion section")
        let normalAgentNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: "## 正式解释\n利率是资金价格。", language: .chinese)
        expect(normalAgentNoteBlock == nil, "non-offline markdown answers are not rewritten by the offline-note extractor")

        let offlineTurnMessages = AgentOfflineTurn.messages(
            question: "解释当前材料",
            sourceTitle: "Mishkin 教材样例",
            input: AgentOfflinePreviewInput(
                language: .chinese,
                question: "解释当前材料",
                hasMaterial: true,
                materialTitle: "Mishkin 教材样例",
                materialText: "利率是资金使用价格的表达。",
                noteTitle: "货币金融学课程 HTML",
                noteText: "## 摘录",
                selectionTitle: nil,
                selectionText: nil
            )
        )
        expect(offlineTurnMessages.count == 2
            && offlineTurnMessages[0].role == .user
            && offlineTurnMessages[0].text == "解释当前材料"
            && offlineTurnMessages[0].source == "Mishkin 教材样例"
            && offlineTurnMessages[1].role == .assistant
            && offlineTurnMessages[1].text.contains("## 离线草稿")
            && offlineTurnMessages[1].text.contains("未配置密钥；这里只整理当前可见内容")
            && offlineTurnMessages[1].source == "Mishkin 教材样例"
            && offlineTurnMessages[1].isUsableAgentAnswer, "offline agent turn appends a visible user turn and writable local draft without an API key")

        let fontDirectoryURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Resources/Fonts")
        let displayFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiStele.ttf")
        let monoFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiSteleMono.ttf")
        CTFontManagerRegisterFontsForURL(displayFontURL as CFURL, .process, nil)
        CTFontManagerRegisterFontsForURL(monoFontURL as CFURL, .process, nil)
        expect(NSFont(name: "WeiBeiStele-Regular", size: 18) != nil
            && NSFont(name: "WeiBeiSteleMono-Regular", size: 13) != nil, "bundled WeiBei English fonts register under their PostScript names")
        let emptyWorkspaceEntryFont = CTFontCreateWithName("WeiBeiStele-Regular" as CFString, 22, nil)
        let emptyWorkspaceEntryCharacters = Array("DOCCHATNOTES".utf16)
        var emptyWorkspaceEntryGlyphs = Array(repeating: CGGlyph(), count: emptyWorkspaceEntryCharacters.count)
        expect(emptyWorkspaceEntryCharacters.withUnsafeBufferPointer { characters in
            emptyWorkspaceEntryGlyphs.withUnsafeMutableBufferPointer { glyphs in
                CTFontGetGlyphsForCharacters(emptyWorkspaceEntryFont, characters.baseAddress!, glyphs.baseAddress!, characters.count)
            }
        } && emptyWorkspaceEntryGlyphs.allSatisfy { $0 != 0 }, "WeiBeiStele keeps every glyph required by the DOC, CHAT, and NOTES work entries")

        func inspectCalligraphyAsset(_ url: URL) throws -> (width: Int, height: Int, visible: Int, transparent: Int, opaqueWhite: Int, outerInk: Int) {
            let data = try Data(contentsOf: url)
            guard let bitmap = NSBitmapImageRep(data: data) else {
                throw NSError(domain: "WeiBeiSelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable calligraphy PNG: \(url.path)"])
            }
            var visible = 0
            var transparent = 0
            var opaqueWhite = 0
            var outerInk = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.alphaComponent > 0.05 {
                        visible += 1
                        if x < 2 || y < 2 || x >= bitmap.pixelsWide - 2 || y >= bitmap.pixelsHigh - 2 {
                            outerInk += 1
                        }
                    } else {
                        transparent += 1
                    }
                    if color.alphaComponent > 0.95
                        && color.redComponent > 0.95
                        && color.greenComponent > 0.95
                        && color.blueComponent > 0.95 {
                        opaqueWhite += 1
                    }
                }
            }
            return (bitmap.pixelsWide, bitmap.pixelsHigh, visible, transparent, opaqueWhite, outerInk)
        }

        let calligraphyDirectoryURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Resources/Inspiration/Calligraphy", isDirectory: true)
        let clearBreezeStats = try inspectCalligraphyAsset(calligraphyDirectoryURL.appendingPathComponent("lanting-clear-breeze.png"))
        let universeStats = try inspectCalligraphyAsset(calligraphyDirectoryURL.appendingPathComponent("lanting-universe.png"))
        expect(clearBreezeStats.width == 856 && clearBreezeStats.height == 132
            && universeStats.width == 624 && universeStats.height == 132
            && clearBreezeStats.visible > 1_000 && universeStats.visible > 1_000
            && clearBreezeStats.transparent > clearBreezeStats.visible
            && universeStats.transparent > universeStats.visible
            && clearBreezeStats.opaqueWhite == 0 && universeStats.opaqueWhite == 0
            && clearBreezeStats.outerInk == 0 && universeStats.outerInk == 0, "bundled Lanting calligraphy masks are transparent, uncropped, and free of hard white backgrounds")

        let inspirationSourcesURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Resources/Inspiration/SOURCES.md")
        let inspirationSources = (try? String(contentsOf: inspirationSourcesURL, encoding: .utf8)) ?? ""
        expect(inspirationSources.contains("a133647a8695cd06d0f5c6215d66e0b8b8d93d56")
            && inspirationSources.contains("b30c54279d2e0b5c7b8221369962ba3a3c0e16b264808332da38cb1b8e63d936")
            && inspirationSources.contains("a915d1e460c68a0634c2cfaad90f802fda04ea8c25227632cd4812c51647df22")
            && inspirationSources.contains("1c7965b6447392a874ed75adb1ce5703f26b562b8fc5fd6f380d1fdde0621379")
            && inspirationSources.contains("Public Domain Mark 1.0")
            && inspirationSources.contains("故00002597")
            && inspirationSources.contains("were rejected")
            && inspirationSources.contains("No NC, ND")
            && inspirationSources.contains("No generative fill, vector tracing, or font substitution"), "inspiration resource documentation preserves source hashes, public-domain status, provenance, exclusions, and transformation limits")

    }
}
