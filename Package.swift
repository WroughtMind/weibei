// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeiBei",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WeiBei", targets: ["WeiBei"]),
        .executable(name: "WeiBeiSelfCheck", targets: ["WeiBeiSelfCheck"]),
        .executable(name: "WeiBeiWebEditorCheck", targets: ["WeiBeiWebEditorCheck"]),
        .executable(name: "WeiBeiPiCheck", targets: ["WeiBeiPiCheck"]),
        .executable(name: "WeiBeiPDFTextWorker", targets: ["WeiBeiPDFTextWorker"]),
        .executable(name: "WeiBeiDevTool", targets: ["WeiBeiDevTool"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            exact: "1.7.1"
        )
    ],
    targets: [
        .target(
            name: "WeiBeiCore",
            resources: [
                .copy("AgentResources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "WeiBei",
            dependencies: ["WeiBeiCore"],
            exclude: ["WebEditor"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "WeiBeiSelfCheck",
            dependencies: ["WeiBeiCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "WeiBeiWebEditorCheck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "WeiBeiPiCheck",
            dependencies: ["WeiBeiCore"]
        ),
        .executableTarget(
            name: "WeiBeiPDFTextWorker",
            linkerSettings: [
                .linkedFramework("PDFKit")
            ]
        ),
        .target(
            name: "WeiBeiDevCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "WeiBeiDevTool",
            dependencies: [
                "WeiBeiDevCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "WeiBeiDevCoreTests",
            dependencies: ["WeiBeiDevCore"]
        ),
        .testTarget(
            name: "WeiBeiCoreTests",
            dependencies: ["WeiBeiCore"]
        ),
        .testTarget(
            name: "WeiBeiAppTests",
            dependencies: [
                "WeiBei",
                "WeiBeiCore",
                "WeiBeiDevCore"
            ]
        ),
        .testTarget(
            name: "WeiBeiDevToolTests",
            dependencies: [
                "WeiBeiDevCore",
                "WeiBeiDevTool",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
