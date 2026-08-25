import Foundation

/// 保存失败的身份:kind 供测试与逻辑判断,message 是失败现场生成的展示文案。
/// 测试断言 kind,不断言 message 字眼(2026-08-25 测试审计定案)。
struct WorkspaceSaveFailure: Equatable {
    enum Kind: Equatable {
        /// 课程已创建/登记,但可携带状态未写入;本机内容已保留,可重试。
        case coursePortableStateUnwritten
        /// 课程状态读不出,课程文件没有被覆盖。
        case courseStateUnreadable
        /// 课程可携带状态没有成功保存;修改仍在当前会话中,尚未安全保存。
        case coursePortableStateUnsaved
        /// 工作区更改尚未写入磁盘;修改仍在当前会话中,尚未安全保存。
        case workspaceChangesUnwritten
        /// 课程状态提交时检测到并发变更,已停止覆盖。
        case courseStateConcurrentConflict
        /// 可携带状态超过 32 MB,原状态保持不变。
        case coursePortableStateOversized
        /// 课程文件夹中的课程状态无法安全更新,原状态已保留。
        case coursePortableStateBlocked
    }

    let kind: Kind
    let message: String
}

/// 重要横幅的类型化身份,与 importantOperationError 展示文案并行记录:
/// 供快照恢复、笔记写入安全保留等需要按语义断言的场景使用;
/// 其余横幅仍走纯字符串通道,不强行类型化。
enum ImportantOperationNotice: Equatable {
    /// 工作区总账本曾损坏,已自动恢复到最近的好备份。
    case snapshotRecovered
    /// 总账本损坏且无可用备份,课程文件夹未受影响。
    case snapshotDamagedNoBackup
    /// 笔记写入/备份/重读/确认受阻:魏碑已停止覆盖,未写内容保留在魏碑中,可重试。
    case noteWriteSafetyHold(fileName: String)
}
