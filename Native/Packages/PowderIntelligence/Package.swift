// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PowderIntelligence", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PowderIntelligence", targets: ["PowderIntelligence"])],
    dependencies: [.package(path: "../PowderCore")],
    targets: [.target(name: "PowderIntelligence", dependencies: ["PowderCore"]),
              .testTarget(name: "PowderIntelligenceTests", dependencies: ["PowderIntelligence", "PowderCore"])])
