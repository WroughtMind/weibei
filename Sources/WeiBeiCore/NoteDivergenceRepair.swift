import CryptoKit
import Foundation

/// P0 笔记持久化止血：默认模板形态判定 + 启动修复例程的纯判定逻辑。
///
/// 判定与执行分离：WorkspaceStore 负责采集现场（读盘 digest、lstat 指纹、
/// 草稿层）并执行写回/清理，本文件只做纯函数决策，便于 WeiBeiSelfCheck
/// 用临时目录 fixture 验证修复清单，再谈执行。
public enum NoteTemplateShape {
    /// 与 WorkspaceStore.defaultNotebookNote 对应的小节标题（中/英双语）。
    /// 修改模板文案时必须同步这里，SelfCheck 有源码断言锁定。
    public static let sectionHeadingVariants: [[String]] = [
        ["核心要点", "Key Points"],
        ["摘录", "Excerpts"],
        ["待追问", "Follow-up Questions"],
    ]

    /// 结构判定：首个非空行是 `# <title>`，其余非空行依次是三个模板小节
    /// 标题（中英任一），小节正文均为空。允许首尾及节间空白行数量差异。
    ///
    /// 用于识别「读盘失败回退出来的默认模板」，避免把它当作真实正文写回磁盘。
    public static func isDefaultTemplateShape(_ markdown: String, title: String) -> Bool {
        guard !title.isEmpty else { return false }
        let nonBlankLines = markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard nonBlankLines.count == sectionHeadingVariants.count + 1,
              nonBlankLines[0] == "# \(title)" else {
            return false
        }
        for (index, variants) in sectionHeadingVariants.enumerated() {
            let line = nonBlankLines[index + 1]
            guard variants.contains(where: { line == "## \($0)" }) else {
                return false
            }
        }
        return true
    }
}

/// 启动修复例程对单个笔记的处置动作。
public enum NoteRepairAction: String, Equatable, Sendable {
    /// 无需处置（幂等收敛后的稳态，或现场不足以安全决策）。
    case none
    /// 草稿≠磁盘且磁盘文件可辨认：备份磁盘现内容 → 草稿原子写回 → 刷指纹 → 清草稿。
    case restoreDraft
    /// 磁盘==草稿：草稿冗余，仅清草稿（内容不动，保证幂等），顺带刷指纹。
    case discardRedundantDraft
    /// 草稿呈模板形态但磁盘不是模板：草稿疑似「读盘失败回退模板」的降级产物，
    /// 清草稿、保磁盘、绝不写盘。
    case discardSuspectTemplateDraft
    /// 无草稿、指纹漂移、磁盘内容可信（==上次自写/==记录 digest）：仅刷新指纹。
    case refreshIdentityOnly
}

/// 修复判定的现场输入。所有 digest 均为 SHA256 hex（与 WorkspaceStore 口径一致）。
public struct NoteRepairItemState: Equatable, Sendable {
    /// notesByItemID 草稿的 digest；nil 表示无草稿。
    public var draftDigest: String?
    /// 草稿是否为默认模板形态（NoteTemplateShape.isDefaultTemplateShape）。
    public var draftIsTemplateShape: Bool
    /// 磁盘文件当前 digest；nil 表示文件不存在或不可读。
    public var diskDigest: String?
    /// defaultNote 模板 digest（用于辨认磁盘内容是否就是模板）。
    public var templateDigest: String?
    /// 持久化指纹与 lstat 现场不符（含持久化指纹缺失）。
    public var identityDrifted: Bool
    /// lstat 成功取到现场指纹。
    public var liveIdentityAvailable: Bool
    /// 上次自写 digest（lastSelfWrittenNoteDigestsByItemID）。
    public var lastSelfWrittenDigest: String?
    /// workspace.json 中记录的 contentDigest。
    public var recordedContentDigest: String?

    public init(
        draftDigest: String?,
        draftIsTemplateShape: Bool,
        diskDigest: String?,
        templateDigest: String?,
        identityDrifted: Bool,
        liveIdentityAvailable: Bool,
        lastSelfWrittenDigest: String?,
        recordedContentDigest: String?
    ) {
        self.draftDigest = draftDigest
        self.draftIsTemplateShape = draftIsTemplateShape
        self.diskDigest = diskDigest
        self.templateDigest = templateDigest
        self.identityDrifted = identityDrifted
        self.liveIdentityAvailable = liveIdentityAvailable
        self.lastSelfWrittenDigest = lastSelfWrittenDigest
        self.recordedContentDigest = recordedContentDigest
    }
}

public enum NoteDivergenceRepairPlanner {
    /// 内容寻址的 SHA256 hex，与 WorkspaceStore.noteContentDigest 口径一致。
    public static func contentDigest(of string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 纯函数判定。安全等级从高到低：
    /// 1. 文件不可读 → 不决策（保留草稿等下次启动）；
    /// 2. 磁盘==草稿 → 只清草稿不动内容（幂等）；
    /// 3. 模板形态草稿 vs 非模板磁盘 → 只清草稿不写盘（防模板二次覆盖）；
    /// 4. 草稿写回要求「路径上的文件就是笔记本体」：指纹未漂移，或磁盘内容
    ///    可按 digest 辨认（模板/上次自写/记录值）；盲态一律不动；
    /// 5. 无草稿时仅在指纹漂移且内容可信时刷指纹。
    public static func action(for state: NoteRepairItemState) -> NoteRepairAction {
        if let draftDigest = state.draftDigest {
            guard let diskDigest = state.diskDigest else {
                return .none
            }
            if diskDigest == draftDigest {
                return .discardRedundantDraft
            }
            if state.draftIsTemplateShape, diskDigest != state.templateDigest {
                return .discardSuspectTemplateDraft
            }
            let diskRecognizable = !state.identityDrifted
                || diskDigest == state.templateDigest
                || diskDigest == state.lastSelfWrittenDigest
                || diskDigest == state.recordedContentDigest
            guard diskRecognizable else {
                return .none
            }
            return .restoreDraft
        }
        guard state.identityDrifted,
              state.liveIdentityAvailable,
              let diskDigest = state.diskDigest else {
            return .none
        }
        let diskContentTrusted = diskDigest == state.lastSelfWrittenDigest
            || diskDigest == state.recordedContentDigest
        return diskContentTrusted ? .refreshIdentityOnly : .none
    }
}
