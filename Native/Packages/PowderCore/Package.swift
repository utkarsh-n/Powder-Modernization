// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowderCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PowderCore", targets: ["PowderCore"])],
    targets: [
        .target(name: "PowderCore"),
        .testTarget(name: "PowderCoreTests", dependencies: ["PowderCore"])
    ]
)
