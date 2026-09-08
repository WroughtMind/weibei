// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatRendererLab",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WeiBeiChatRendererLab", targets: ["ChatRendererLab"]),
        .library(name: "ChatRendererKit", targets: ["ChatRendererKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/MarkdownView",
                 revision: "757b6fcc4b3095e84f4c0613f4b98147f49dcd09"),
        .package(url: "https://github.com/Lakr233/Litext", exact: "2.2.1")
    ],
    targets: [
        .target(name: "ChatRendererKit", dependencies: [
            .product(name: "MarkdownView", package: "MarkdownView"),
            .product(name: "MarkdownParser", package: "MarkdownView"),
            .product(name: "Litext", package: "Litext")
        ]),
        .executableTarget(name: "ChatRendererLab", dependencies: [
            "ChatRendererKit",
            .product(name: "MarkdownView", package: "MarkdownView")
        ])
    ]
)
