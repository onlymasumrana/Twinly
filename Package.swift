// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Twinly",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Twinly", targets: ["Twinly"]),
        .executable(name: "TwinlyLauncher", targets: ["TwinlyLauncher"]),
        .executable(name: "TwinlyTestsRunner", targets: ["TwinlyTestsRunner"]),
        .library(name: "TwinlyCore", targets: ["TwinlyCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TwinlyCore",
            dependencies: [],
            path: "Sources/TwinlyCore"
        ),
        .executableTarget(
            name: "TwinlyLauncher",
            dependencies: [],
            path: "Sources/TwinlyLauncher"
        ),
        .executableTarget(
            name: "Twinly",
            dependencies: ["TwinlyCore"],
            path: "Sources/Twinly"
        ),
        .executableTarget(
            name: "TwinlyTestsRunner",
            dependencies: ["TwinlyCore"],
            path: "Tests/TwinlyTests"
        )
    ]
)
