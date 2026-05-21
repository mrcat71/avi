// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Avi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GitKit", targets: ["GitKit"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .executable(name: "AviApp", targets: ["AviApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    ],
    targets: [
        .target(name: "GitKit"),
        .target(name: "AppUI", dependencies: ["GitKit"]),
        .executableTarget(name: "AviApp", dependencies: ["AppUI"]),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"]),
        .testTarget(
            name: "AppUITests",
            dependencies: [
                "AppUI",
                "GitKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
