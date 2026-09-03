import Foundation

// WeiBeiDev：开发工具子命令（不引入任何外部依赖，手写 CommandLine 分发）。
// 子命令：
//   selfcheck-assertions          吸收 script/check_selfcheck_source_assertions.sh
//   verify-release-metadata       吸收 script/verify_release_metadata.sh
//   verify-release-architecture   校验 App 与全部嵌套 Mach-O 的目标架构
//   verify-production-hygiene     吸收 script/verify_production_hygiene.sh
//   nslog-scan                    防回潮：Sources/ 下断言无 NSLog 调用

// 仓库根由源码位置推导（Sources/WeiBeiDev/main.swift -> 仓库根），
// 不依赖调用方 cwd。
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Sources/WeiBeiDev
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // 仓库根

func fail(_ message: String) -> Never {
    fputs("WeiBeiDev check failed: \(message)\n", stderr)
    exit(1)
}

func fail(_ message: String, exitCode: Int32) -> Never {
    fputs("WeiBeiDev check failed: \(message)\n", stderr)
    exit(exitCode)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("WeiBeiDev check failed: \(message)\n", stderr)
        exit(1)
    }
}

/// 跑 git 命令，返回 stdout（trim 后）；失败返回 nil。
/// 先读 stdout 再 wait（避免大输出填满 pipe 缓冲导致死锁）。
func runGit(_ arguments: [String], in directory: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 读文件内容（UTF-8），读不到返回空字符串。
func readText(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

/// 执行一个只读命令并返回 trim 后的 stdout；失败返回 nil。
private func runCommand(_ executable: String, arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - selfcheck-assertions

private func enumerateSwiftFiles(in directory: URL) -> [URL] {
    let files = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )) ?? []
    return files.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
}

func runSelfcheckAssertions() {
    let selfCheckDirectory = repositoryRoot.appendingPathComponent("Sources/WeiBeiSelfCheck")
    // 源码字符串探针（Source.contains( / Source.range( 行）必须紧邻 SAFETY: 理由；
    // `let ... readSource(` 行是纯取值辅助，跳过。
    var bad: [String] = []
    for file in enumerateSwiftFiles(in: selfCheckDirectory) {
        let lines = readText(file).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.hasPrefix("let ") && line.contains("readSource(") {
                continue
            }
            let isFileSourceProbe = line.contains("Source.contains(") || line.contains("Source.range(")
            if !isFileSourceProbe { continue }
            let windowStart = max(0, index - 8)
            let windowEnd = min(lines.count, index + 30)
            let window = lines[windowStart..<windowEnd].joined(separator: "\n")
            if !window.contains("SAFETY:") {
                let snippet = String(stripped.prefix(100))
                bad.append("\(file.lastPathComponent):\(index + 1): \(snippet)")
            }
        }
    }
    if !bad.isEmpty {
        var message = "source-string probes without a nearby SAFETY reason:\n"
        for item in bad { message += "  \(item)\n" }
        fail(message, exitCode: 1)
    }
    print("WeiBei SelfCheck source-assertion guard passed")
}

// MARK: - verify-release-metadata

func runVerifyReleaseMetadata(arguments: [String]) {
    var appBundle = repositoryRoot.appendingPathComponent("dist/魏碑.app")
    var appBundleSet = false
    var requireClean = false
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--require-clean":
            requireClean = true
        case "--help", "-h":
            fputs("usage: WeiBeiDev verify-release-metadata [--require-clean] [path/to/魏碑.app]\n", stderr)
            exit(0)
        case _ where argument.hasPrefix("-"):
            fputs("usage: WeiBeiDev verify-release-metadata [--require-clean] [path/to/魏碑.app]\n", stderr)
            exit(2)
        default:
            if appBundleSet {
                fputs("usage: WeiBeiDev verify-release-metadata [--require-clean] [path/to/魏碑.app]\n", stderr)
                exit(2)
            }
            appBundle = URL(fileURLWithPath: argument)
            appBundleSet = true
        }
    }

    let versionFile = repositoryRoot.appendingPathComponent("VERSION")
    guard FileManager.default.fileExists(atPath: versionFile.path) else {
        fail("missing VERSION", exitCode: 3)
    }
    let infoPlist = appBundle.appendingPathComponent("Contents/Info.plist")
    let appBinary = appBundle.appendingPathComponent("Contents/MacOS/WeiBei")
    let appIcon = appBundle.appendingPathComponent("Contents/Resources/AppIcon.icns")
    let appIconAssets = appBundle.appendingPathComponent("Contents/Resources/Assets.car")
    let legalDirectory = appBundle.appendingPathComponent("Contents/Resources/Legal")
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: infoPlist.path),
          fileManager.isExecutableFile(atPath: appBinary.path),
          fileManager.fileExists(atPath: appIcon.path),
          fileManager.fileExists(atPath: appIconAssets.path) else {
        fail("incomplete app bundle at \(appBundle.path)", exitCode: 4)
    }
    for legalFile in ["PRIVACY.md", "THIRD_PARTY_NOTICES.md", "ASSET_ATTRIBUTIONS.md"] {
        let url = legalDirectory.appendingPathComponent(legalFile)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              (attributes[.size] as? Int ?? 0) > 0 else {
            fail("missing packaged notice \(legalFile)", exitCode: 10)
        }
    }
    // Pre-1.0 包不得把未来 1.0.0 发布计划散文当作现行法律副本打包。
    if fileManager.fileExists(atPath: legalDirectory.appendingPathComponent("v1.0.0.md").path) {
        fail("packaged Legal must not include future v1.0.0 release notes", exitCode: 11)
    }
    if runGit(["rev-parse", "--is-shallow-repository"], in: repositoryRoot) == "true" {
        fail("full Git history is required for a stable build number", exitCode: 5)
    }

    let expectedVersion = readText(versionFile)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard expectedVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
        fail("VERSION must use numeric major.minor.patch", exitCode: 6)
    }
    guard let expectedCommit = runGit(["rev-parse", "--verify", "HEAD"], in: repositoryRoot) else {
        fail("cannot resolve HEAD", exitCode: 6)
    }
    guard let expectedBuild = runGit(["rev-list", "--count", expectedCommit], in: repositoryRoot) else {
        fail("cannot count commits", exitCode: 6)
    }
    let statusOutput = runGit(["status", "--porcelain=v1", "--untracked-files=normal"], in: repositoryRoot) ?? ""
    let expectedDirty = !statusOutput.isEmpty
    if requireClean && expectedDirty {
        fail("a formal package must come from a clean worktree", exitCode: 7)
    }

    guard let plistData = try? Data(contentsOf: infoPlist),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
          let plistDictionary = plist as? [String: Any] else {
        fail("cannot parse Info.plist at \(infoPlist.path)", exitCode: 8)
    }
    func plistString(_ key: String) -> String {
        plistDictionary[key] as? String ?? ""
    }
    let actualVersion = plistString("CFBundleShortVersionString")
    let actualBuild = plistString("CFBundleVersion")
    let actualCommit = plistString("WeiBeiGitCommit")
    let actualDirtyBool = plistDictionary["WeiBeiSourceDirty"] as? Bool ?? false
    let actualDirty = actualDirtyBool ? "true" : "false"
    let actualBundleID = plistString("CFBundleIdentifier")
    let actualIcon = plistString("CFBundleIconFile")
    let actualIconName = plistString("CFBundleIconName")
    let actualMinSystem = plistString("LSMinimumSystemVersion")
    let requiresSignedFeed = plistDictionary["SURequireSignedFeed"] as? Bool ?? false
    let verifiesUpdateBeforeExtraction = plistDictionary["SUVerifyUpdateBeforeExtraction"] as? Bool ?? false

    func assertEqual(_ label: String, _ expected: String, _ actual: String) {
        if actual != expected {
            fail("\(label) expected \(expected), got \(actual)", exitCode: 8)
        }
    }
    assertEqual("version", expectedVersion, actualVersion)
    assertEqual("build", expectedBuild, actualBuild)
    assertEqual("commit", expectedCommit, actualCommit)
    assertEqual("source dirty state", expectedDirty ? "true" : "false", actualDirty)
    assertEqual("bundle identifier", "com.changfenhuang.weibei", actualBundleID)
    assertEqual("app icon file", "AppIcon", actualIcon)
    assertEqual("app icon name", "AppIcon", actualIconName)
    assertEqual("minimum system version", "14.0", actualMinSystem)
    guard requiresSignedFeed, verifiesUpdateBeforeExtraction else {
        fail(
            "Sparkle requires signed-feed and verify-before-extraction safeguards",
            exitCode: 8
        )
    }

    guard let iconHeader = try? Data(contentsOf: appIcon).prefix(4),
          String(data: iconHeader, encoding: .ascii) == "icns" else {
        fail("AppIcon.icns has an invalid header", exitCode: 9)
    }
    guard let assetHeader = try? Data(contentsOf: appIconAssets).prefix(8),
          String(data: assetHeader, encoding: .ascii) == "BOMStore" else {
        fail("Assets.car has an invalid header", exitCode: 9)
    }

    print("release_metadata_version=\(actualVersion)")
    print("release_metadata_build=\(actualBuild)")
    print("release_metadata_commit=\(actualCommit)")
    print("release_metadata_source_dirty=\(actualDirty)")
    print("release_metadata_bundle_id=\(actualBundleID)")
    print("release_metadata_icon=\(actualIcon)")
    print("release_metadata_icon_assets=enabled")
    print("release_metadata_min_system=\(actualMinSystem)")
    print("release_metadata_sparkle_validation=enabled")
    print("release_metadata_notices=packaged")
}

// MARK: - verify-release-architecture

func runVerifyReleaseArchitecture(arguments: [String]) {
    guard arguments.count == 2,
          ["arm64", "x86_64"].contains(arguments[0]) else {
        fputs("usage: WeiBeiDev verify-release-architecture <arm64|x86_64> <path/to/魏碑.app>\n", stderr)
        exit(2)
    }

    let expectedArchitecture = arguments[0]
    // FileManager may enumerate a /var-based mount through its canonical
    // /private/var path. Canonicalize the bundle root so required-binary URL
    // comparisons use the same spelling as enumerated URLs.
    let appBundle = URL(fileURLWithPath: arguments[1]).resolvingSymlinksInPath()
    let contents = appBundle.appendingPathComponent("Contents", isDirectory: true)
    let infoPlist = contents.appendingPathComponent("Info.plist")
    guard let plistData = try? Data(contentsOf: infoPlist),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
          let plistDictionary = plist as? [String: Any] else {
        fail("cannot parse Info.plist at \(infoPlist.path)", exitCode: 3)
    }

    let declaredArchitecture = plistDictionary["WeiBeiArchitecture"] as? String ?? ""
    let feedURL = plistDictionary["SUFeedURL"] as? String ?? ""
    guard declaredArchitecture == expectedArchitecture else {
        fail(
            "WeiBeiArchitecture expected \(expectedArchitecture), got \(declaredArchitecture)",
            exitCode: 4
        )
    }
    guard feedURL.hasSuffix("/appcast-\(expectedArchitecture).xml") else {
        fail("SUFeedURL does not select appcast-\(expectedArchitecture).xml", exitCode: 5)
    }

    let fileManager = FileManager.default
    let binaryRoots = ["MacOS", "Helpers", "Frameworks"].map {
        contents.appendingPathComponent($0, isDirectory: true)
    }
    var machOBinaries: [URL] = []
    for root in binaryRoots where fileManager.fileExists(atPath: root.path) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { continue }
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegular,
                  let fileDescription = runCommand("/usr/bin/file", arguments: ["-b", url.path]),
                  fileDescription.contains("Mach-O") else { continue }
            machOBinaries.append(url)
        }
    }

    let appBinary = contents.appendingPathComponent("MacOS/WeiBei")
    let helperBinary = contents.appendingPathComponent("Helpers/WeiBeiPDFTextWorker")
    for requiredBinary in [appBinary, helperBinary] where !machOBinaries.contains(requiredBinary) {
        fail("missing required Mach-O binary \(requiredBinary.path)", exitCode: 6)
    }
    guard !machOBinaries.isEmpty else {
        fail("app bundle contains no Mach-O binaries", exitCode: 6)
    }

    for binary in machOBinaries.sorted(by: { $0.path < $1.path }) {
        guard let architectures = runCommand("/usr/bin/lipo", arguments: ["-archs", binary.path]) else {
            fail("cannot inspect architectures for \(binary.path)", exitCode: 7)
        }
        let architectureSet = Set(architectures.split(separator: " ").map(String.init))
        guard architectureSet.contains(expectedArchitecture) else {
            fail(
                "\(binary.path) lacks \(expectedArchitecture); found \(architectures)",
                exitCode: 8
            )
        }
        if binary == appBinary || binary == helperBinary,
           architectureSet != Set([expectedArchitecture]) {
            fail(
                "native executable \(binary.path) must contain only \(expectedArchitecture); found \(architectures)",
                exitCode: 9
            )
        }
    }

    print("release_architecture=\(expectedArchitecture)")
    print("release_architecture_macho_count=\(machOBinaries.count)")
    print("release_architecture_feed=\(feedURL)")
}

// MARK: - verify-production-hygiene

private let forbiddenBinaryMarkers = [
    "WEIBEI_VERIFY_SCENARIO",
    "WEIBEI_SUPPRESS_ACTIVATION",
    "WEIBEI_FORCE_OFFLINE_AGENT",
    "WEIBEI_SAFETY_TEST_MODE",
    "WEIBEI_PDF_WORKER_SAFETY_TEST",
    "--self-check-imported-identity",
    "--self-check-course-project-root",
    "--self-check-background-workspace-save",
    "--safety-probe",
    "verification-state.txt",
    "weibei:verify-interaction",
    "offline-learning-flow",
    "A0C_GHOST_CHAT_TOKEN",
    "DO_NOT_TRASH.txt",
    "sample-html",
    "sample-pdf",
    "sample-md",
    "Mishkin 教材样例",
    "内置示例",
    "PDF 阅读样例",
    "ForSelfCheck",
    "SelfCheckTrash",
    "capturesAgentRequestForSelfCheck",
    "usesBackgroundWorkspacePersistenceForSelfCheck",
    "pauseWorkspacePersistenceForSelfCheck",
]

private let forbiddenResourceMarkers = [
    "WEIBEI_VERIFY_SCENARIO",
    "weibei:verify-interaction",
    "self-check-spec",
    "RichAnswerVerification",
    "verification-only",
    "Vendor/PiRuntime/",
    "prepare_pi_runtime.sh",
    "PiRuntime/bin/pi",
]

private let retiredRuntimeResourceDirectories = ["PiRuntime", "BunRuntime"]

private let forbiddenTestResourceNames = [
    "rich_answer_worker_self_test.py",
    "weibei-single-pendulum-color-contrast-original.png",
]

private func filesRecursively(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [] }
    var result: [URL] = []
    for case let url as URL in enumerator where !url.hasDirectoryPath {
        result.append(url)
    }
    return result
}

private func dataContains(_ data: Data, _ marker: String) -> Bool {
    data.range(of: Data(marker.utf8)) != nil
}

/// 与旧 shell 一致：可执行文件用 /usr/bin/strings 提取可打印字符串再搜标记
/// （避免把 Swift mangled 符号名里的子串误判为泄漏的测试字符串）。
/// 先读 stdout 再 wait（strings 对 release 二进制输出可能远超 pipe 缓冲）。
private func stringsOutput(of executable: URL) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
    process.arguments = [executable.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return ""
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func runVerifyProductionHygiene(arguments: [String]) {
    let fileManager = FileManager.default
    let defaultBundle = repositoryRoot.appendingPathComponent("dist/魏碑.app")
    let appBundle: URL
    if let first = arguments.first {
        appBundle = URL(fileURLWithPath: first)
    } else {
        appBundle = defaultBundle
    }
    let infoPlist = appBundle.appendingPathComponent("Contents/Info.plist")
    guard let plistData = try? Data(contentsOf: infoPlist),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
          let plistDictionary = plist as? [String: Any],
          let executableName = plistDictionary["CFBundleExecutable"] as? String else {
        fail("missing app bundle at \(appBundle.path)", exitCode: 2)
    }
    let appBinary = appBundle
        .appendingPathComponent("Contents/MacOS/\(executableName)")
    guard fileManager.isExecutableFile(atPath: appBinary.path) else {
        fail("missing executable \(appBinary.path)", exitCode: 3)
    }

    var executables = [appBinary]
    let helpers = appBundle.appendingPathComponent("Contents/Helpers")
    if let enumerator = FileManager.default.enumerator(
        at: helpers,
        includingPropertiesForKeys: [.isExecutableKey],
        options: [.skipsHiddenFiles]
    ) {
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            if fileManager.isExecutableFile(atPath: url.path) {
                executables.append(url)
            }
        }
    }
    for executable in executables {
        let strings = stringsOutput(of: executable)
        for marker in forbiddenBinaryMarkers {
            if strings.contains(marker) {
                fail("\(executable.path) contains '\(marker)'", exitCode: 4)
            }
        }
    }

    let resources = appBundle.appendingPathComponent("Contents/Resources")
    let resourceFiles = filesRecursively(in: resources)
    for file in resourceFiles {
        if file.pathComponents.contains(where: { retiredRuntimeResourceDirectories.contains($0) }) {
            fail("packaged retired runtime resource \(file.path)", exitCode: 7)
        }
        if let data = try? Data(contentsOf: file),
           let marker = forbiddenResourceMarkers.first(where: { dataContains(data, $0) }) {
            fail("resources contain '\(marker)'", exitCode: 6)
        }
        let name = file.lastPathComponent.lowercased()
        let baseName = file.lastPathComponent
        if name.contains("verification")
            || forbiddenTestResourceNames.contains(baseName) {
            fail("packaged test resource \(file.path)", exitCode: 5)
        }
    }

    print("production_hygiene=clean")
}

// MARK: - nslog-scan（防回潮）

// 运行时拼接，避免 WeiBeiDev 自身源码出现 NSLog 调用字面量而自指误报。
private let nsLogCallMarker = "NS" + "Log("

func runNSLogScan() {
    let sources = repositoryRoot.appendingPathComponent("Sources")
    var offenders: [(path: String, count: Int)] = []
    guard let enumerator = FileManager.default.enumerator(
        at: sources,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        fail("cannot scan Sources/")
    }
    for case let url as URL in enumerator where !url.hasDirectoryPath && url.pathExtension == "swift" {
        // 白名单：WeiBeiLog.swift 是统一日志门面自身（防御性保留）。
        if url.lastPathComponent == "WeiBeiLog.swift" { continue }
        let text = readText(url)
        let count = text.components(separatedBy: nsLogCallMarker).count - 1
        if count > 0 {
            offenders.append((url.path, count))
        }
    }
    if !offenders.isEmpty {
        var message = "NSLog 调用不得回归 Sources/：\n"
        for offender in offenders.sorted(by: { $0.path < $1.path }) {
            message += "  \(offender.path): \(offender.count)\n"
        }
        fail(message, exitCode: 1)
    }
    print("WeiBeiDev nslog-scan passed")
}

// MARK: - 分发

let allArguments = CommandLine.arguments
guard allArguments.count >= 2 else {
    fputs("""
    usage: WeiBeiDev <subcommand> [args]
      selfcheck-assertions [--self-check]
      verify-release-metadata [--require-clean] [path/to/魏碑.app]
      verify-release-architecture <arm64|x86_64> <path/to/魏碑.app>
      verify-production-hygiene [path/to/魏碑.app]
      nslog-scan
    """, stderr)
    exit(2)
}

let subcommand = allArguments[1]
let subArguments = Array(allArguments.dropFirst(2))

switch subcommand {
case "selfcheck-assertions":
    // 与旧 shell 一致：--self-check 仅自检夹具标记逻辑（不依赖真实仓库）。
    if subArguments.first == "--self-check" {
        let fixture = "expect(workspaceStoreSource.contains(\"guard !noteDivergenceRepairDidRun else { return }\"),\n    \"SAFETY:note-repair-oneshot keep this\")"
        if !fixture.contains("SAFETY:note-repair-oneshot") {
            fail("self-check fixture missing SAFETY tag", exitCode: 1)
        }
        print("WeiBei SelfCheck source-assertion guard self-check passed")
        exit(0)
    }
    runSelfcheckAssertions()
case "verify-release-metadata":
    runVerifyReleaseMetadata(arguments: subArguments)
case "verify-release-architecture":
    runVerifyReleaseArchitecture(arguments: subArguments)
case "verify-production-hygiene":
    runVerifyProductionHygiene(arguments: subArguments)
case "nslog-scan":
    runNSLogScan()
default:
    fputs("unknown WeiBeiDev subcommand: \(subcommand)\n", stderr)
    exit(2)
}
