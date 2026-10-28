import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[2]),
      let application = NSRunningApplication(processIdentifier: pid) else {
    exit(2)
}
if CommandLine.arguments[1] == "quit" {
    exit(application.terminate() ? 0 : 1)
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let visible = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid
        && ($0[kCGWindowLayer as String] as? Int) == 0
        && ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0
}
let result: [String: Any] = [
    "pid": pid, "terminated": application.isTerminated,
    "finished_launching": application.isFinishedLaunching,
    "visible_windows": visible,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
