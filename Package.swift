// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TermiPad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TermiPad", targets: ["TermiPad"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TermiPad",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "TermiPadTests",
            dependencies: ["TermiPad"],
            path: "Tests/TermiPadTests"
        )
    ]
)
