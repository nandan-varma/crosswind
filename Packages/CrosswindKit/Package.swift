// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CrosswindKit",
    platforms: [.macOS(.v27)],
    products: [.library(name: "CrosswindKit", targets: ["CrosswindKit"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.39.0"),
    ],
    targets: [
        .target(
            name: "CrosswindKit",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .testTarget(name: "CrosswindKitTests", dependencies: ["CrosswindKit"]),
    ]
)
