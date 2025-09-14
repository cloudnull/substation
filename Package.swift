// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "otui",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OTClient", targets: ["OTClient"]),
        .executable(name: "otui", targets: ["otui"])
    ],
    dependencies: [],
    targets: [
        .target(name: "OTClient"),
        .systemLibrary(
            name: "CNCurses",
            pkgConfig: "ncurses",
            providers: [
                .brew(["ncurses"]),
                .apt(["libncurses-dev"])
            ]
        ),
        .executableTarget(
            name: "otui",
            dependencies: ["OTClient", "CNCurses"]
        ),
        .testTarget(
            name: "OTClientTests",
            dependencies: ["OTClient"]
        )
    ]
)
