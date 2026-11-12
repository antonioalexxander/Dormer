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
            resources: [.copy("Resources/runtimes.json"), .copy("Resources/winetricks-curated.json")]
        ),
        .target(name: "BottleManager", dependencies: ["DormerCore", "WineManager"]),
        .target(name: "DormerUI", dependencies: ["DormerCore", "WineManager", "BottleManager"]),
        .testTarget(name: "DormerCoreTests", dependencies: ["DormerCore"]),
        .testTarget(name: "WineManagerTests", dependencies: ["WineManager"]),
        .testTarget(name: "BottleManagerTests", dependencies: ["BottleManager", "WineManager"]),
    ]
)
