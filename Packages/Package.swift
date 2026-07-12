// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommandlyPackages",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "CommandKit", targets: ["CommandKit"]),
        .library(name: "SearchKit", targets: ["SearchKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
        .library(name: "ExtensionKit", targets: ["ExtensionKit"]),
        .library(name: "Observability", targets: ["Observability"]),
        .library(name: "CalculatorKit", targets: ["CalculatorKit"])
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: []
        ),
        .target(
            name: "CommandKit",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "SearchKit",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "DesignSystem",
            dependencies: []
        ),
        .target(
            name: "Infrastructure",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "Persistence",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "SecurityKit",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "ExtensionKit",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "Observability",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "CalculatorKit",
            dependencies: ["AppCore"]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"]
        ),
        .testTarget(
            name: "CommandKitTests",
            dependencies: ["CommandKit"]
        ),
        .testTarget(
            name: "SearchKitTests",
            dependencies: ["SearchKit"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        ),
        .testTarget(
            name: "SecurityKitTests",
            dependencies: ["SecurityKit"]
        ),
        .testTarget(
            name: "ExtensionKitTests",
            dependencies: ["ExtensionKit"]
        ),
        .testTarget(
            name: "ObservabilityTests",
            dependencies: ["Observability"]
        ),
        .testTarget(
            name: "CalculatorKitTests",
            dependencies: ["CalculatorKit"]
        )
    ]
)
