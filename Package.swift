// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Computah",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Computah", targets: ["Computah"])],
    targets: [
        .executableTarget(name: "Computah"),
        .testTarget(name: "ComputahTests", dependencies: ["Computah"])
    ]
)
