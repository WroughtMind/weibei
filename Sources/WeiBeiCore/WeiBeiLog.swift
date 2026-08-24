import Foundation
import os

/// 统一日志门面。事件用 notice、错误用 error（这两级 logd 会落盘持久化；
/// debug/info 默认只进内存，等于没记）。严格不记用户正文/课程/笔记内容、
/// 文件路径、各类 ID、error.localizedDescription 原文；报错文本
/// （网页错误、Agent 诊断）例外可记，截断 500 字符。
/// 所有插值必须显式 privacy: .public，否则系统默认脱敏为 <private>。
public enum WeiBeiLog {
    public static let subsystem = "com.changfenhuang.weibei"
    public static let workspace  = Logger(subsystem: subsystem, category: "workspace")
    public static let noteRepair = Logger(subsystem: subsystem, category: "noteRepair")
    public static let web        = Logger(subsystem: subsystem, category: "web")

    /// 报错文本统一截断，防无界长度。
    public static func truncated(_ text: String, limit: Int = 500) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    /// 错误只记 domain.code，不记 localizedDescription 原文。
    public static func code(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain).\(ns.code)"
    }
}
