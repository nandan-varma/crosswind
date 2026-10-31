// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "display-spike",
    platforms: [.macOS(.v27)],
    dependencies: [.package(path: "../../Packages/CrosswindKit")],
    targets: [.executableTarget(name: "dev", dependencies: ["CrosswindKit"], path: "Sources/dev")]
)
