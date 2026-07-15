import Darwin
import Foundation
import PDFKit

private enum PDFTextWorkerExit: Int32 {
    case invalidArguments = 2
    case resourceLimit = 3
    case unreadablePage = 4
}

private struct WorkerResponse: Encodable {
    var pages: [WorkerPage]
}

private struct WorkerPage: Encodable {
    var pageIndex: Int
    var status: String
    var text: String
}

private func fail(_ reason: PDFTextWorkerExit) -> Never {
    exit(reason.rawValue)
}

private func applyResourceLimits() {
    var cpuLimit = rlimit(rlim_cur: 3, rlim_max: 3)
    guard setrlimit(RLIMIT_CPU, &cpuLimit) == 0 else {
        fail(.resourceLimit)
    }
}

private func runVerificationProbe(_ name: String) -> Never {
    switch name {
    case "normal":
        FileHandle.standardOutput.write(Data("verification-ok\n".utf8))
    case "timeout":
        Thread.sleep(forTimeInterval: 5)
    case "output":
        FileHandle.standardOutput.write(Data(repeating: 65, count: 2 * 1_024 * 1_024))
    case "memory":
        var allocation = Data(count: 256 * 1_024 * 1_024)
        allocation.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            for offset in stride(from: 0, to: bytes.count, by: 4_096) {
                baseAddress.storeBytes(of: UInt8(1), toByteOffset: offset, as: UInt8.self)
            }
        }
        withExtendedLifetime(allocation) {
            Thread.sleep(forTimeInterval: 5)
        }
    default:
        fail(.invalidArguments)
    }
    exit(0)
}

applyResourceLimits()

if ProcessInfo.processInfo.environment["WEIBEI_PDF_WORKER_VERIFY"] == "1",
   CommandLine.arguments.count == 3,
   CommandLine.arguments[1] == "--verification-probe" {
    runVerificationProbe(CommandLine.arguments[2])
}

guard CommandLine.arguments.count == 4,
      let maximumCharacters = Int(CommandLine.arguments[3]),
      maximumCharacters > 0,
      maximumCharacters <= 1_000_000 else {
    fail(.invalidArguments)
}
let pageIndexes = CommandLine.arguments[2]
    .split(separator: ",")
    .compactMap { Int($0) }
guard !pageIndexes.isEmpty,
      pageIndexes.count <= 16,
      pageIndexes.allSatisfy({ $0 >= 0 }) else {
    fail(.invalidArguments)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let document = PDFDocument(url: url) else {
    fail(.unreadablePage)
}

let maximumUTF8Bytes = maximumCharacters * 4
private let pages = pageIndexes.map { pageIndex -> WorkerPage in
    guard pageIndex < document.pageCount,
          let rawText = document.page(at: pageIndex)?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
        return WorkerPage(pageIndex: pageIndex, status: "missing", text: "")
    }
    var text = ""
    text.reserveCapacity(min(rawText.count, maximumCharacters))
    var utf8Bytes = 0
    for character in rawText.prefix(maximumCharacters) {
        let characterBytes = String(character).utf8.count
        guard utf8Bytes + characterBytes <= maximumUTF8Bytes else { break }
        text.append(character)
        utf8Bytes += characterBytes
    }
    return WorkerPage(
        pageIndex: pageIndex,
        status: rawText.count > text.count ? "partial" : "complete",
        text: text
    )
}
guard let output = try? JSONEncoder().encode(WorkerResponse(pages: pages)) else {
    fail(.unreadablePage)
}
FileHandle.standardOutput.write(output)
