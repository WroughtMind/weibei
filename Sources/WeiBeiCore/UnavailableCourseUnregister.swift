import Foundation

/// Policy for unregistering a course whose folder is unavailable.
/// The only allowed action is `removeCourseFromWeiBei`, which drops the
/// registration and relations and must not move or delete external files.
public enum UnavailableCourseUnregister {
    public static func shouldOfferUnregister(
        rootURL: URL?,
        unavailableReason: String?
    ) -> Bool {
        rootURL == nil || unavailableReason != nil
    }

    public static func confirmationTitle(chinese: Bool) -> String {
        chinese ? "只从魏碑移除这门课程？" : "Remove this course from WeiBei only?"
    }

    public static func confirmationMessage(chinese: Bool) -> String {
        chinese
            ? "会移除课程登记和关系，不移动、不删除任何外部文件或备份。"
            : "This removes the course registration and relations. It does not move or delete any external files or backups."
    }
}
