// swift-tools-version: 6.2
// The engine libraries below the runtime, one module per layer. The app and openskycli
// link these products through OpenSky.xcodeproj; OpenSky.xcworkspace holds both. A
// module lists every module it uses, so the compiler rejects an upward import
// (docs/tools/modules.md).

import PackageDescription

/// The same language settings as Config/Build/Base.xcconfig. Change both together.
let testSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .treatAllWarnings(as: .error)
]

/// Library code keeps the engine's main-actor default, so moving a file between modules
/// never changes its isolation. Test code keeps the nonisolated default of the test bundles.
let librarySettings: [SwiftSetting] = testSettings + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "OpenSky",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenSkyFormats", targets: ["OpenSkyFormats"]),
        .library(name: "OpenSkyGameData", targets: ["OpenSkyGameData"]),
        .library(name: "FormatsTestSupport", targets: ["FormatsTestSupport"])
    ],
    targets: [
        .target(
            name: "OpenSkyFormats",
            swiftSettings: librarySettings
        ),
        .target(
            name: "OpenSkyGameData",
            dependencies: ["OpenSkyFormats"],
            swiftSettings: librarySettings
        ),
        .target(
            name: "FormatsTestSupport",
            dependencies: ["OpenSkyFormats"],
            path: "Tests/FormatsTestSupport",
            exclude: ["AGENTS.md", "CLAUDE.md"],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "OpenSkyFormatsTests",
            dependencies: ["OpenSkyFormats", "FormatsTestSupport"],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "OpenSkyGameDataTests",
            dependencies: ["OpenSkyGameData", "FormatsTestSupport"],
            swiftSettings: testSettings
        )
    ],
    swiftLanguageModes: [.v6]
)
