// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [.library(name: "Core", targets: ["Core"])],
    targets: [
        .target(name: "Core", resources: [.copy("RepDB"), .process("Localizable.xcstrings")]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
