// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmartCapture",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "SmartCapture",
            path: "Sources/SmartCapture",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
