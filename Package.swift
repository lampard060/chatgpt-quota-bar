// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatGPTQuotaBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChatGPTQuotaBar", targets: ["ChatGPTQuotaBar"]),
    ],
    targets: [
        .executableTarget(name: "ChatGPTQuotaBar"),
        .testTarget(
            name: "ChatGPTQuotaBarTests",
            dependencies: ["ChatGPTQuotaBar"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
