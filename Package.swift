// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Avi",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "GitKit", targets: ["GitKit"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .executable(name: "AviApp", targets: ["AviApp"]),
    ],
    targets: [
        .target(name: "GitKit"),
        .target(name: "AppUI", dependencies: ["GitKit"]),
        .executableTarget(name: "AviApp", dependencies: ["AppUI"]),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"]),
    ]
)
