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
        .executable(name: "WeiBeiRelationCheck", targets: ["WeiBeiRelationCheck"]),
        .executable(name: "WeiBeiWebEditorCheck", targets: ["WeiBeiWebEditorCheck"])
    ],
    targets: [
        .target(
            name: "WeiBeiCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision")
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
            name: "WeiBeiRelationCheck",
            dependencies: ["WeiBeiCore"]
        )
    ]
)
