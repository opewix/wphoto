// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WPhoto",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WPhoto", path: "Sources/WPhoto")
    ]
)
