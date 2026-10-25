// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [.library(name: "Core", targets: ["Core"])],
    targets: [
        .target(name: "Core", resources: [.process("exercises.json")]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
