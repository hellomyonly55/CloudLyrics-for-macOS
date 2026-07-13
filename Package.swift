// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudLyrics",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CloudLyrics", targets: ["CloudLyrics"])],
    targets: [
        .executableTarget(
            name: "CloudLyrics",
            path: "Sources/CloudLyrics",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CloudLyricsTests",
            dependencies: ["CloudLyrics"],
            path: "Tests/CloudLyricsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
