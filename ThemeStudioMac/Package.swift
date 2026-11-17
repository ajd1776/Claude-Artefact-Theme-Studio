// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ThemeStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ThemeStudio", path: "Sources/ThemeStudio")
    ]
)
