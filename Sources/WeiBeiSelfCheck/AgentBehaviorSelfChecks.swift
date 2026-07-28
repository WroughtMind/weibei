import Foundation
import Security
import WeiBeiCore

/**
 * 验证 Agent 提示、凭证、阅读线索与 Markdown 行为。
 */
enum AgentBehaviorSelfChecks {
    /**
     * 执行该领域的自检。
     */
    static func run(repositoryURL: URL) throws {
        let data = Data("""
        {"output":[{"content":[{"type":"output_text","text":"只根据当前材料回答。"}]}]}
        """.utf8)
        let text = try OpenAIResponsesClient.extractText(from: data)
        expect(text == "只根据当前材料回答。", "response parser")
        let groundedPrompt = OpenAIResponsesClient.composePrompt(
            question: "解释金融体系",
            materialTitle: "Mishkin 教材样例",
            materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
            noteTitle: "利率笔记",
            noteText: "## 摘录\n金融体系和利率相关。",
            selectionTitle: "Mishkin 教材样例，第 1 页选区",
            selectionText: "储蓄者的资金转移给有投资机会的人",
            recentMessages: [
                AgentMessage(role: .user, text: "上一问", source: "利率笔记")
            ]
        )
        expect(groundedPrompt.input.contains("当前材料：Mishkin 教材样例"), "agent prompt includes material title")
        expect(groundedPrompt.input.contains("当前笔记：利率笔记"), "agent prompt includes note title")
        expect(groundedPrompt.input.contains("当前选区（来源：Mishkin 教材样例，第 1 页选区）："), "agent prompt includes selection source")
        expect(groundedPrompt.input.contains("用户（来源：利率笔记）：上一问"), "agent prompt keeps recent message source")
        expect(groundedPrompt.instructions.contains("来源依据") && groundedPrompt.instructions.contains("没有用到的来源不要列"), "agent prompt requires grounded source evidence")
        expect(groundedPrompt.instructions.contains("学习助手") && !groundedPrompt.instructions.contains("学习 Agent"), "agent prompt speaks as a study assistant instead of internal agent copy")
        let multiSelectionPrompt = OpenAIResponsesClient.composePrompt(
            question: "比较这些片段",
            materialTitle: "Mishkin 教材样例",
            materialText: "金融体系与利率。",
            noteTitle: "利率笔记",
            noteText: "",
            selectionTitle: "2 个已选文本片段",
            selectionText: """
            片段 1（来源：Mishkin 教材样例，第 1 页）：
            金融体系转移资金。

            片段 2（来源：利率笔记）：
            利率是资金使用价格。
            """,
            recentMessages: []
        )
        expect(multiSelectionPrompt.input.contains("当前选区（来源：2 个已选文本片段）：")
            && multiSelectionPrompt.input.contains("片段 1（来源：Mishkin 教材样例，第 1 页）：")
            && multiSelectionPrompt.input.contains("片段 2（来源：利率笔记）："), "agent prompt can carry multiple selected text attachments with source labels")
        let assistantDialoguePrompt = OpenAIResponsesClient.composePrompt(
            question: "继续解释",
            materialTitle: "Mishkin 教材样例",
            materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
            noteTitle: "利率笔记",
            noteText: "",
            selectionText: nil,
            recentMessages: [
                AgentMessage(role: .assistant, text: "上一答", source: nil)
            ]
        )
        expect(assistantDialoguePrompt.input.contains("助手：上一答")
            && !assistantDialoguePrompt.input.contains("Agent：上一答"), "assistant dialogue turns avoid internal agent labels")
        let currentPagePrompt = OpenAIResponsesClient.composePrompt(
            question: "解释当前页",
            materialTitle: "Mishkin 教材样例，第 3 页",
            materialText: "第 1 页\n旧页面内容\n\n第 3 页\n当前页内容\n\n第 4 页\n后续页面内容",
            noteTitle: "利率笔记",
            noteText: "",
            selectionText: nil,
            recentMessages: []
        )
        expect(currentPagePrompt.input.contains("当前材料：Mishkin 教材样例，第 3 页")
            && currentPagePrompt.input.contains("第 3 页\n当前页内容")
            && !currentPagePrompt.input.contains("旧页面内容")
            && !currentPagePrompt.input.contains("后续页面内容"), "agent prompt focuses PDF material text on the current reader page when the material title has a page reference")
        let noteOnlyPrompt = OpenAIResponsesClient.composePrompt(
            question: "整理这段",
            materialTitle: "未选择材料",
            materialText: "",
            noteTitle: "概念笔记",
            noteText: "实际利率需要区分通胀预期。",
            selectionText: "实际利率",
            recentMessages: []
        )
        expect(noteOnlyPrompt.input.contains("当前材料：无") && noteOnlyPrompt.input.contains("当前选区（来源：概念笔记）："), "note-only prompt anchors selection to the current note")
        let englishPrompt = OpenAIResponsesClient.composePrompt(
            question: "Summarize this",
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "Real interest rates account for expected inflation.",
            selectionTitle: "",
            selectionText: "real interest rates",
            recentMessages: [
                AgentMessage(role: .assistant, text: "Earlier answer", source: "Current note")
            ],
            language: .english
        )
        expect(
            englishPrompt.input.contains("Current material: none")
                && englishPrompt.input.contains("Current note: Current note")
                && englishPrompt.input.contains("Current selection (source: Current note):")
                && englishPrompt.input.contains("Assistant (source: Current note): Earlier answer")
                && englishPrompt.instructions.contains("Answer in English")
                && englishPrompt.instructions.contains("Sources used")
                && !englishPrompt.input.contains("当前笔记"),
            "agent prompt has a complete English note-only mode"
        )
        expect(OpenAIAPIKeyStore.cleaned("  sk-test\n") == "sk-test", "api key cleaning")

        do {
            let temporaryKeychainURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-selfcheck-\(UUID().uuidString).keychain-db")
            let temporaryKeychainPassword = Data("weibei-selfcheck-only".utf8)
            var temporaryKeychain: SecKeychain?
            let createStatus = temporaryKeychainURL.path.withCString { path in
                temporaryKeychainPassword.withUnsafeBytes { password in
                    SecKeychainCreate(path, UInt32(password.count), password.baseAddress, false, nil, &temporaryKeychain)
                }
            }
            expect(createStatus == errSecSuccess && temporaryKeychain != nil, "isolated self-check keychain is created without changing the user's default keychain")
            guard let temporaryKeychain else { exit(1) }
            defer {
                SecKeychainDelete(temporaryKeychain)
            }

            let temporaryCredentialStore = WeiBeiCredentialStore(
                service: "com.changfenhuang.weibei.selfcheck.\(UUID().uuidString)",
                account: "OPENAI_API_KEY",
                keychain: temporaryKeychain
            )
            try? temporaryCredentialStore.delete()
            try temporaryCredentialStore.save("  sk-selfcheck\n")
            expect(temporaryCredentialStore.load() == "sk-selfcheck", "isolated credential store save and load")
            try temporaryCredentialStore.delete()
            expect(temporaryCredentialStore.load().isEmpty, "isolated credential store delete")

            // Production path: file under Application Support, no login-keychain UI.
            let fileService = "com.changfenhuang.weibei.selfcheck.file.\(UUID().uuidString)"
            let fileStore = WeiBeiCredentialStore(service: fileService, account: "TEST_KEY")
            try? fileStore.delete()
            try fileStore.save(" sk-file-store \n")
            expect(fileStore.load() == "sk-file-store", "WeiBei app-data credential file save and load")
            try fileStore.delete()
            expect(fileStore.load().isEmpty, "WeiBei app-data credential file delete")
        }

        expect(
            {
                let paths = SelfCheckSupport.source("Sources/WeiBeiCore/WeiBeiAgentDataPaths.swift", repositoryURL: repositoryURL)
                let oauth = SelfCheckSupport.source("Sources/WeiBei/Support/PiOAuthService.swift", repositoryURL: repositoryURL)
                let runtime = SelfCheckSupport.source("Sources/WeiBeiCore/PiAgentRuntime.swift", repositoryURL: repositoryURL)
                return paths.contains("enum WeiBeiAgentDataPaths")
                    && paths.contains("piAuthJSON")
                    && oauth.contains("WeiBeiAgentDataPaths.piAuthJSON")
                    && !oauth.contains("homeAuthURL")
                    && runtime.contains("WeiBeiAgentDataPaths.piAgentDirectory")
                    && !runtime.contains("homeDirectoryForCurrentUser.appendingPathComponent(\".pi/agent\"")
            }(),
            "OAuth and Pi config use WeiBei Application Support paths, not terminal ~/.pi"
        )

        let missingSelectionInsight = QuietInsight.make(
            materialTitle: "利率资料",
            materialText: "实际利率扣除了通货膨胀后的购买力变化。",
            noteText: "# 利率资料\n",
            selectionText: "实际利率扣除了通货膨胀后的购买力变化。"
        )
        expect(missingSelectionInsight.body.contains("还没有进入笔记"), "selection insight")

        let coveredMaterialInsight = QuietInsight.make(
            materialTitle: "利率资料",
            materialText: "实际利率扣除了通货膨胀后的购买力变化。",
            noteText: "实际利率扣除了通货膨胀后的购买力变化。",
            selectionText: nil
        )
        expect(coveredMaterialInsight.body.contains("已经覆盖"), "covered material insight")
        let noteOnlyInsight = QuietInsight.make(
            materialTitle: "新概念笔记",
            materialText: "",
            noteText: "实际利率需要区分名义利率和通胀预期。",
            selectionText: nil
        )
        expect(noteOnlyInsight.body.contains("当前笔记有一条") && !noteOnlyInsight.body.contains("先导入"), "note-only quiet insight uses note context")
        expect(noteOnlyInsight.noteBlock.contains("来源：新概念笔记"), "note-only quiet insight keeps note source")
        expect(noteOnlyInsight.noteBlock.contains("> [!note] 阅读线索\n>\n>") && !noteOnlyInsight.noteBlock.contains("静默洞察"), "quiet insight writes as a readable callout instead of a noisy bullet")
        let coveredNoteSelectionInsight = QuietInsight.make(
            materialTitle: "新概念笔记",
            materialText: "",
            noteText: "实际利率需要区分名义利率和通胀预期。",
            selectionText: "实际利率需要区分名义利率和通胀预期。"
        )
        expect(!coveredNoteSelectionInsight.body.contains("当前材料其他段落"), "covered note selection avoids fake material relation")
        let agentInsight = QuietInsight.agent(materialTitle: "利率资料", answer: "这份材料更适合先补通胀预期这一层。")
        expect(agentInsight?.body.contains("通胀预期") == true, "agent insight keeps answer")
        expect(agentInsight?.noteBlock.contains("> [!note] 阅读线索\n>\n>") == true && agentInsight?.noteBlock.contains("Agent 洞察") == false, "agent insight writes the same quiet reading-line callout")
        expect(QuietInsight.agent(materialTitle: "利率资料", answer: "   \n") == nil, "empty agent insight is ignored")
        let markdownNoiseInsight = QuietInsight.make(
            materialTitle: "Markdown 验收",
            materialText: """
            ![image](missing.png)
            | 能力 | 状态 |
            | --- | --- |
            - [ ] todo
            删除线、重点高亮、货币理论、新概念笔记。
            """,
            noteText: "",
            selectionText: nil
        )
        expect(!markdownNoiseInsight.body.contains("[image]"), "quiet insight ignores markdown image syntax")
        expect(markdownNoiseInsight.body.contains("货币理论"), "quiet insight keeps readable markdown prose")
        let foldedCalloutInsight = QuietInsight.make(
            materialTitle: "Callout 验收",
            materialText: """
            > [!note]-折叠标题不应泄漏控制符
            >
            > 利率是资金使用价格的表达。
            """,
            noteText: "",
            selectionText: nil
        )
        expect(!foldedCalloutInsight.body.contains("[!note]")
            && !foldedCalloutInsight.body.contains("-折叠标题"), "quiet insight removes Obsidian callout control and fold markers")
        let calloutSelectionText = MarkdownSelectionSanitizer.clean("""
        [!quote] 选区摘录
        利率是资金使用价格的表达。
        """)
        expect(calloutSelectionText == "选区摘录\n利率是资金使用价格的表达。", "selection sanitizer removes visible Obsidian callout control markers from rendered selections")
        let quotedCalloutSelectionText = MarkdownSelectionSanitizer.clean("""
        > [!warning]- 风险提示
        > 普通美元 $5 不应被误伤。
        """)
        expect(!quotedCalloutSelectionText.contains("[!warning]")
            && quotedCalloutSelectionText.contains("风险提示")
            && quotedCalloutSelectionText.contains("$5"), "selection sanitizer handles quoted and folded callouts without damaging ordinary prose")
        let readableMarkdownSelectionText = MarkdownSelectionSanitizer.clean("""
        ==重点==<br />
        [[货币理论|理论别名]]
        [[货币理论\\|表格别名]]
        ![曲线图|120x80](assets/curve.png)
        ![[assets/curve.png|180]]
        ~~删除线~~、`代码`、^[脚注说明]
        %%内部注释%%
        - [x] 已完成项
        """)
        let expectedReadableMarkdownSelectionText = """
        重点
        理论别名
        表格别名
        曲线图
        assets/curve.png
        删除线、代码、脚注说明
        已完成项
        """
        expect(readableMarkdownSelectionText == expectedReadableMarkdownSelectionText, "selection sanitizer turns common Markdown and Obsidian writing syntax into readable text for Agent context")
        let searchableTags = MarkdownTagSearch.tags(in: """
        ---
        tags:
          - property/rate
          - "#quoted-tag"
        ---

        # 标题不是标签
        正文标签 #finance/rate 和 #nested/tag
        行内代码 `#not-tag` 不应该进入标签

        ```swift
        let tag = "#code-tag"
        ```
        """)
        expect(searchableTags == ["#finance/rate", "#nested/tag", "#property/rate", "#quoted-tag"], "markdown tag search extracts real prose and frontmatter property tags")
        expect(MarkdownTagSearch.tags(in: "---\ntags: [banking, #macro/rate]\n---\n正文") == ["#banking", "#macro/rate"], "markdown tag search reads inline frontmatter tag arrays")
    }
}
