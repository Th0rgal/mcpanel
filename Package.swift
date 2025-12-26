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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MCPanel",
            dependencies: [],
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
