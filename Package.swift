// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "vimba",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "vimba",
            path: "Sources/vimba",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
