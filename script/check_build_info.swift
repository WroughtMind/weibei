import Foundation

@main
struct CheckBuildInfo {
    static func main() throws {
        let info = WeiBeiAppBuildInfo(version: "0.0.1", build: "20260909.1530.27", commit: "123456789", isDirty: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: info.buildDate!)
        precondition(local.year == 2026 && local.month == 9 && local.day == 9)
        precondition(local.hour == 23 && local.minute == 30 && local.second == 27)
        var invalid = info
        invalid.build = "20260229.1530.27"
        precondition(invalid.buildDate == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": info.build], format: .xml, options: 0)
        try plist.write(to: directory.appendingPathComponent("Info.plist"))
        precondition(WeiBeiAppBuildInfo.current(bundle: Bundle(path: directory.path)!).build == info.build)
        print("build info checks passed")
    }
}
