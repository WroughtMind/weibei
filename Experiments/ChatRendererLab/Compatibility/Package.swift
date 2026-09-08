// swift-tools-version: 6.0
import PackageDescription

// A link probe, NOT the production package and NOT a renderer comparison.
// Keep the two WeiBei dependency constraints exactly as on main@429a86f.
let package = Package(
    name: "WeiBeiRendererCompatibility",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LinkedRenderersProbe", targets: ["LinkedRenderersProbe"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/MarkdownView",
                 revision: "757b6fcc4b3095e84f4c0613f4b98147f49dcd09"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3"),
        .package(url: "https://github.com/WroughtMind/SwiftMath",
                 revision: "b6d15610552aa04a54c36bf205efaf34409dc335")
    ],
    targets: [
        .executableTarget(name: "LinkedRenderersProbe", dependencies: [
            .product(name: "MarkdownView", package: "MarkdownView"),
            .product(name: "MarkdownParser", package: "MarkdownView"),
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "SwiftMath", package: "SwiftMath")
        ])
    ]
)
