// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenAgentDashboard",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "OpenAgentDashboard", targets: ["OpenAgentDashboard"])
    ],
    targets: [
        .target(
            name: "OpenAgentDashboard",
            path: "OpenAgentDashboard"
        )
    ]
)
