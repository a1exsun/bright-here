// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "bright-here",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "BrightHereCore", targets: ["BrightHereCore"]),
        .executable(name: "bright-here", targets: ["BrightHereApp"]),
        .executable(name: "bright-here-cli", targets: ["BrightHereCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "BrightHereCore"
        ),
        .executableTarget(
            name: "BrightHereApp",
            dependencies: [
                "BrightHereCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "BrightHereCLI",
            dependencies: ["BrightHereCore"]
        ),
        .testTarget(
            name: "BrightHereCoreTests",
            dependencies: ["BrightHereCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
