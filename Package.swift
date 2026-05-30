// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Avi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GitKit", targets: ["GitKit"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .executable(name: "AviApp", targets: ["AviApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.2"),
        .package(url: "https://github.com/airbnb/lottie-spm", from: "4.6.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0")
    ],
    targets: [
        .target(name: "GitKit"),
        .target(
            name: "AppUI",
            dependencies: [
                "GitKit",
                .product(name: "Lottie", package: "lottie-spm"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern")
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "AviApp", dependencies: ["AppUI", "GitKit"]),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"]),
        .testTarget(
            name: "AppUITests",
            dependencies: [
                "AppUI",
                "GitKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        )
    ]
)
