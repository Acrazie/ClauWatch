// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClauWatch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .target(
            name: "ClauWatchCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/ClauWatchCore"
        ),
        .executableTarget(
            name: "ClauWatch",
            dependencies: ["ClauWatchCore"],
            path: "Sources/ClauWatch",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/Fonts")
            ]
        ),
        .testTarget(
            name: "ClauWatchTests",
            dependencies: ["ClauWatchCore"],
            path: "Tests/ClauWatchTests"
        )
        // SwiftTesting framework available in Swift 5.10+
        // Built-in, no additional dependencies needed
    ]
)
