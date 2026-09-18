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
        .library(name: "CalculatorKit", targets: ["CalculatorKit"]),
        .library(name: "AIKit", targets: ["AIKit"]),
        .library(name: "MarkdownPreviewKit", targets: ["MarkdownPreviewKit"]),
        .library(name: "SystemCompanionKit", targets: ["SystemCompanionKit"]),
        .library(name: "ModuleKit", targets: ["ModuleKit"]),
        .library(name: "ModuleRuntime", targets: ["ModuleRuntime"]),
        .library(name: "AICommandBridge", targets: ["AICommandBridge"]),
        .library(name: "TimersModule", targets: ["TimersModule"])
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
        .target(
            name: "AIKit",
            dependencies: []
        ),
        .target(
            name: "MarkdownPreviewKit",
            dependencies: []
        ),
        .target(name: "SystemCompanionKit", dependencies: ["Infrastructure"]),

        // MARK: Module system
        //
        // ModuleKit holds data-only module metadata and non-UI contracts.
        // ModuleRuntime implements the generic host and must never import a feature target.
        // AICommandBridge adapts commands to AIKit and must never import a feature target.
        .target(name: "ModuleKit", dependencies: ["AppCore", "CommandKit"]),
        .target(name: "ModuleRuntime", dependencies: ["ModuleKit", "CommandKit"]),
        .target(name: "AICommandBridge", dependencies: ["ModuleKit", "CommandKit", "AIKit"]),

        // MARK: Feature modules
        //
        // Feature targets depend on contracts only. They never depend on ModuleRuntime,
        // on the Commandly executable, or on each other.
        .target(
            name: "TimersModule",
            dependencies: ["ModuleKit", "CommandKit", "AppCore"],
            path: "Modules/Timers/Sources/TimersModule"
        ),

        .testTarget(name: "ModuleKitTests", dependencies: ["ModuleKit", "CommandKit"]),
        .testTarget(name: "ModuleRuntimeTests", dependencies: ["ModuleRuntime", "ModuleKit", "CommandKit"]),
        .testTarget(
            name: "AICommandBridgeTests",
            dependencies: ["AICommandBridge", "ModuleKit", "CommandKit", "AIKit"]
        ),
        .testTarget(
            name: "TimersModuleTests",
            dependencies: ["TimersModule", "ModuleKit", "ModuleRuntime", "AICommandBridge", "CommandKit", "AIKit"],
            path: "Modules/Timers/Tests/TimersModuleTests"
        ),
        .testTarget(name: "SystemCompanionKitTests", dependencies: ["SystemCompanionKit", "Infrastructure"]),
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
            name: "InfrastructureTests",
            dependencies: ["Infrastructure"]
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
        ),
        .testTarget(
            name: "AIKitTests",
            dependencies: ["AIKit"]
        ),
        .testTarget(
            name: "MarkdownPreviewKitTests",
            dependencies: ["MarkdownPreviewKit"]
        )
    ]
)
