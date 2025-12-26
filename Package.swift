// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MCPanel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MCPanel", targets: ["MCPanel"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MCPanel",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "mcpanel",
            exclude: [
                "Info.plist",
                "MCPanel.entitlements"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
