// swift-tools-version: 6.0
// DormerKit: toda la lógica de Dormer separada en módulos.
// El target de la app (Dormer.xcodeproj) solo importa `DormerUI`.

import PackageDescription

let package = Package(
    name: "DormerKit",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DormerCore", targets: ["DormerCore"]),
        .library(name: "WineManager", targets: ["WineManager"]),
        .library(name: "BottleManager", targets: ["BottleManager"]),
        .library(name: "DormerUI", targets: ["DormerUI"]),
    ],
    targets: [
        .target(name: "DormerCore"),
        .target(
            name: "WineManager",
            dependencies: ["DormerCore"],
            resources: [
                .copy("Resources/runtimes.json"), .copy("Resources/winetricks-curated.json"),
                .copy("Resources/components.json"), .copy("Resources/cabextract-wrapper.sh"),
            ]
        ),
        .target(name: "BottleManager", dependencies: ["DormerCore", "WineManager"]),
        .target(name: "DormerUI", dependencies: ["DormerCore", "WineManager", "BottleManager"]),
        // Builds synthetic executables and shortcuts for the tests below; not shipped.
        .target(name: "DormerTestSupport", path: "Tests/DormerTestSupport"),
        .testTarget(name: "DormerCoreTests", dependencies: ["DormerCore", "DormerTestSupport"]),
        .testTarget(name: "WineManagerTests", dependencies: ["WineManager", "DormerTestSupport"]),
        .testTarget(name: "BottleManagerTests", dependencies: ["BottleManager", "WineManager", "DormerTestSupport"]),
    ]
)
