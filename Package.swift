// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleFMTerminal",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/StoneHub/apple-fm-swift.git", revision: "5b937241b0236f892af28588e75a78dd557acf21")
    ],
    targets: [
        .executableTarget(name: "apple-fm-terminal-model", dependencies: [
            .product(name: "AppleFM", package: "apple-fm-swift")
        ], path: "Sources/TerminalInference")
    ]
)
