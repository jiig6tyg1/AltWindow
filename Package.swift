// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AltWindow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AltWindow", targets: ["AltWindow"])],
    targets: [
        .executableTarget(name: "AltWindow"),
        .testTarget(name: "AltWindowTests", dependencies: ["AltWindow"])
    ]
)
