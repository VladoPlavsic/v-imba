// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "vimbmac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "vimbmac",
            path: "Sources/vimbmac",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
