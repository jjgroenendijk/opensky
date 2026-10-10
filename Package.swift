// swift-tools-version: 6.2
// The engine, one module per layer, by The Modular Architecture
// (docs/tools/modules.md). Modules are declared bottom-up: a module depends only
// on earlier ones, and a feature depends on another feature's interface only.
// The helpers below stop the manifest from loading when a rule breaks.

import PackageDescription

/// The same language settings as Config/Build/Base.xcconfig. Change both together.
let languageSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .treatAllWarnings(as: .error)
]

/// The vendored decode-only ffmpeg (make ffmpeg). Its headers are on every module's
/// search path because a module that imports OpenSkyAudio also loads CFFmpeg.
let ffmpeg = Context.packageDirectory + "/.vendor/ffmpeg"
let ffmpegHeaders: SwiftSetting = .unsafeFlags(["-Xcc", "-I\(ffmpeg)/include"])

/// Test code keeps the nonisolated default of the Xcode test bundles.
let testSettings = languageSettings + [ffmpegHeaders]

/// Library code keeps the engine's main-actor default, so moving a file between
/// modules never changes its isolation.
let librarySettings = testSettings + [.defaultIsolation(MainActor.self)]

/// CFFmpeg links the three ffmpeg dylibs, so every binary that uses it links them
/// too. Their install names start with @rpath. The app finds them in its bundle and
/// openskycli through its own runpath; a package test executable has neither, so the
/// test targets add the vendored prefix to their runpath here.
let testLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "\(ffmpeg)/lib"])
]

// MARK: - Module helpers

/// Products of external packages (docs/decisions/), keyed by product name. They sit
/// below every module.
let externalProducts = ["ArgumentParser": "swift-argument-parser"]
    .merging(["HeapModule", "DequeModule"].map { ($0, "swift-collections") }) { $1 }

/// Every declared module, in declaration order. The layering checks read it.
nonisolated(unsafe) var declared: [String] = externalProducts.keys.sorted()
/// Feature implementations. Nothing but the composition roots may depend on one.
nonisolated(unsafe) var featureImplementations: Set<String> = []
/// Targets the umbrella products export.
nonisolated(unsafe) var libraryTargets: [String] = []
nonisolated(unsafe) var testingTargets: [String] = []
nonisolated(unsafe) var fixtureTargets: [String] = []

/// Rejects a dependency on a module declared later (the same layer or above), on a
/// feature implementation other than `own`, and on a fixtures library other than
/// `own`'s. Only a test-side library (`testing`) may depend on a testing library.
func checked(
    _ module: String,
    _ dependencies: [String],
    own: String? = nil,
    testing: Bool = false
) -> [Target.Dependency] {
    for dependency in dependencies {
        precondition(
            declared.contains(dependency),
            "\(module) depends on \(dependency), which is not declared below it"
        )
        precondition(
            dependency == own || !featureImplementations.contains(dependency),
            "\(module) depends on the feature implementation \(dependency); use its interface"
        )
        precondition(
            testing || !testingTargets.contains(dependency),
            "\(module) depends on the testing library \(dependency); only tests may"
        )
        precondition(
            dependency == own.map { "\($0)Fixtures" } || !fixtureTargets.contains(dependency),
            "\(module) depends on \(dependency); only that feature's tests may"
        )
    }
    return dependencies.map { dependency in
        externalProducts[dependency].map { .product(name: dependency, package: $0) }
            ?? .target(name: dependency)
    }
}

func testTarget(_ name: String, dependencies: [String]) -> Target {
    .testTarget(
        name: name,
        dependencies: (["TagsTesting"] + dependencies).map { .target(name: $0) },
        swiftSettings: testSettings,
        linkerSettings: testLinkerSettings
    )
}

/// Test targets wait until every library is declared, because a test may link a
/// testing library that sits above the module under test (`EngineTesting` over
/// `OpenSkyGameDataTests`). Order inside the package graph does not matter to SwiftPM.
nonisolated(unsafe) var deferredTests: [Target] = []
func deferTests(_ name: String, dependencies: [String]) {
    deferredTests.append(testTarget(name, dependencies: dependencies))
}

/// A foundation module: a library with a stable public API that every module above
/// may import directly. No interface split. `tests` adds `<name>Tests`.
func foundation(
    _ name: String,
    dependencies: [String] = [],
    exclude: [String] = [],
    swiftSettings extraSettings: [SwiftSetting] = [],
    tests: [String]? = nil
) -> [Target] {
    let library = Target.target(
        name: name,
        dependencies: checked(name, dependencies),
        exclude: exclude,
        swiftSettings: librarySettings + extraSettings
    )
    declared.append(name)
    libraryTargets.append(name)
    if let tests {
        deferTests("\(name)Tests", dependencies: [name] + tests)
    }
    return [library]
}

/// Fakes and fixtures other modules' tests share: `Tests/<name>/`. It depends on
/// interfaces, lower modules, and other testing libraries, never on a feature
/// implementation, so any test may link it.
func testing(_ name: String, dependencies: [String]) -> [Target] {
    let target = Target.target(
        name: name,
        dependencies: checked(name, dependencies, testing: true),
        path: "Tests/\(name)",
        swiftSettings: testSettings
    )
    declared.append(name)
    testingTargets.append(name)
    return [target]
}

/// Fixtures that build `feature`'s own implementation: `Tests/<feature>Fixtures/`.
/// Only `<feature>Tests` and the Xcode test bundles link it, so no other feature's
/// tests reach that implementation through it.
func fixtures(_ feature: String, dependencies: [String]) -> [Target] {
    let name = "\(feature)Fixtures"
    let target = Target.target(
        name: name,
        dependencies: checked(name, dependencies, own: feature, testing: true),
        path: "Tests/\(name)",
        swiftSettings: testSettings
    )
    declared.append(name)
    fixtureTargets.append(name)
    return [target]
}

/// A feature's interface, declared before its implementation because a feature
/// declared earlier needs it. `feature(name, ...)` later finds it and depends on it.
func interface(_ feature: String, dependencies: [String]) -> [Target] {
    let name = "\(feature)Interface"
    let target = Target.target(
        name: name,
        dependencies: checked(name, dependencies),
        swiftSettings: librarySettings
    )
    declared.append(name)
    libraryTargets.append(name)
    return [target]
}

/// A feature module: `<name>` (the implementation), plus `<name>Interface` and
/// `<name>Tests` when the matching argument is non-nil. An interface declared
/// earlier with `interface(_:dependencies:)` is reused.
func feature(
    _ name: String,
    dependencies: [String] = [],
    interface: [String]? = nil,
    swiftSettings extraSettings: [SwiftSetting] = [],
    tests: [String]? = nil
) -> [Target] {
    var targets: [Target] = []
    let interfaceName = "\(name)Interface"
    if let interface {
        targets.append(.target(
            name: interfaceName,
            dependencies: checked(interfaceName, interface),
            swiftSettings: librarySettings + extraSettings
        ))
        declared.append(interfaceName)
        libraryTargets.append(interfaceName)
    }
    let ownInterface = interface != nil || declared.contains(interfaceName) ? [interfaceName] : []
    targets.append(.target(
        name: name,
        dependencies: checked(name, ownInterface + dependencies),
        swiftSettings: librarySettings + extraSettings
    ))
    declared.append(name)
    libraryTargets.append(name)
    featureImplementations.insert(name)
    if let tests {
        deferTests("\(name)Tests", dependencies: [name] + tests)
    }
    return targets
}

/// A module the composition roots share, for code both the app and OpenSkyCLI
/// need that names feature implementations. It may depend on implementations, and
/// no module may depend on it. `tests` adds `<name>Tests`.
func composition(_ name: String, dependencies: [String], tests: [String]? = nil) -> [Target] {
    for dependency in dependencies {
        precondition(
            declared.contains(dependency),
            "\(name) depends on \(dependency), which is not declared below it"
        )
        precondition(
            !testingTargets.contains(dependency),
            "\(name) depends on the testing library \(dependency); only tests may"
        )
    }
    let library = Target.target(
        name: name,
        dependencies: dependencies.map { .target(name: $0) },
        swiftSettings: librarySettings
    )
    declared.append(name)
    libraryTargets.append(name)
    featureImplementations.insert(name)
    if let tests {
        deferTests("\(name)Tests", dependencies: [name] + tests)
    }
    return [library]
}

// MARK: - Modules, bottom-up

/// The structs shared with Metal. The shaders in Sources/Shaders include the same header.
let shaderTypes = Target.target(name: "OpenSkyShaderTypes", publicHeadersPath: ".")
/// The vendored ffmpeg as a clang module (Sources/CFFmpeg/include/module.modulemap).
/// A C target, not a system library: when a testing library shares OpenSkyAudio
/// with the app, Xcode builds OpenSkyAudio as a dynamic framework, and a framework
/// cannot depend on a system-library target ("missing target with GUID
/// 'PACKAGE-TARGET:CFFmpeg'"). A framework also has to resolve every symbol when it
/// links, so the target carries the ffmpeg link flags.
let cffmpeg = Target.target(
    name: "CFFmpeg",
    cSettings: [.unsafeFlags(["-I\(ffmpeg)/include"])],
    linkerSettings: [
        .unsafeFlags(["-L\(ffmpeg)/lib"]),
        .linkedLibrary("avcodec"), .linkedLibrary("avutil"), .linkedLibrary("swresample")
    ]
)
/// The vendored astcenc (make astcenc), a static library behind a C shim. Like
/// CFFmpeg, the target carries the link flags (docs/decisions/astcenc.md).
let astcenc = Context.packageDirectory + "/.vendor/astcenc"
let castcencoder = Target.target(
    name: "CASTCEncoder",
    cxxSettings: [.unsafeFlags(["-I\(astcenc)/include"])],
    linkerSettings: [
        .unsafeFlags(["-L\(astcenc)/lib"]),
        .linkedLibrary("astcenc"),
        .linkedLibrary("c++")
    ]
)
declared += ["OpenSkyShaderTypes", "CFFmpeg", "CASTCEncoder"]

var targets: [Target] = [shaderTypes, cffmpeg, castcencoder]

// The Swift Testing tags every test target links through `testTarget`.
targets += testing("TagsTesting", dependencies: [])

// Foundation

// Formats: a core of binary readers, compression, geometry values, archives and
// string tables, then one module per format family. A family depends only on the
// core, so a parser change rebuilds one family and the modules that use it.
targets += foundation("OpenSkyFormatsCore", tests: ["FormatsTesting"])
/// CPU loops such as the chargen face paint and the Papyrus interpreter run up to 100
/// times slower unoptimized, so Debug builds them optimized too.
let optimizedInDebug: [SwiftSetting] = [.unsafeFlags(["-O"], .when(configuration: .debug))]
targets += foundation("OpenSkyImageKernels", swiftSettings: optimizedInDebug)
let formatFamilies = ["ESM", "Mesh", "Animation", "Audio", "PEX", "SWF", "ESS"]
for family in formatFamilies {
    let module = "OpenSkyFormats\(family)"
    let kernels = family == "Mesh" ? ["OpenSkyImageKernels"] : []
    targets += foundation(
        module,
        dependencies: ["OpenSkyFormatsCore"] + kernels,
        tests: ["FormatsTesting", "OpenSkyFormatsCore"] + kernels
    )
}

// Byte builders and fixtures for every format family in one library, so a parser
// test links one target. The families stay apart in Sources/.
targets += testing(
    "FormatsTesting",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsAnimation",
        "OpenSkyFormatsAudio", "OpenSkyFormatsPEX", "OpenSkyFormatsSWF", "OpenSkyFormatsESS"
    ]
)

targets += foundation(
    "OpenSkyGameData",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyFormatsPEX",
        "OpenSkyFormatsSWF"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "FormatsTesting", "OpenSkyFormatsPEX",
        "EngineTesting"
    ]
)
targets += foundation(
    "OpenSkyBehavior",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "OpenSkyGameData"],
    tests: [
        "EngineTesting", "OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "FormatsTesting",
        "OpenSkyFormatsMesh", "OpenSkyGameData"
    ]
)

// The asset cache folder: entries, staleness, and the size limit. Loaders above
// it read converted assets from it (docs/engine/asset-cache.md).
targets += foundation(
    "OpenSkyAssetCache",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsMesh", "OpenSkyGameData"],
    tests: ["OpenSkyFormatsCore", "OpenSkyFormatsMesh", "OpenSkyGameData", "FormatsTesting"]
)
targets += foundation(
    "OpenSkyLaunch",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"],
    tests: ["OpenSkyFormatsCore", "OpenSkyGameData", "FormatsTesting"]
)
targets += foundation("OpenSkyDiagnostics", dependencies: ["OpenSkyShaderTypes"])
// The agent control protocol, socket, and router; the app and openskycli both link it.
targets += foundation("OpenSkyAgentControl", tests: [])
targets += foundation(
    "OpenSkyPhysics",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyAssetCache"
    ],
    tests: [
        "EngineTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "FormatsTesting", "OpenSkyGameData"
    ]
)

targets += foundation(
    "OpenSkyAudio",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAudio", "OpenSkyGameData",
        "CFFmpeg", "OpenSkyAssetCache"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAudio", "OpenSkyGameData",
        "FormatsTesting", "OpenSkyAssetCache"
    ]
)

targets += foundation(
    "OpenSkyRendering",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF",
        "OpenSkyGameData", "OpenSkyDiagnostics", "OpenSkyPhysics", "OpenSkyShaderTypes",
        "OpenSkyAssetCache", "CASTCEncoder"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyPhysics", "OpenSkyShaderTypes", "FormatsTesting", "OpenSkyFormatsSWF",
        "EngineTesting", "OpenSkyAssetCache"
    ]
)

targets += foundation(
    "OpenSkyWorldState",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "FormatsTesting", "EngineTesting"
    ]
)
targets += foundation(
    "OpenSkyConditions",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState"
    ]
)

// Fixtures over the engine foundation: game data, behavior, physics, rendering, and
// world state.
targets += testing(
    "EngineTesting",
    dependencies: [
        "FormatsTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAnimation",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyWorldState"
    ]
)

// Features

// Interfaces declared ahead of their implementations, because features below them
// need their values.
targets += interface(
    "OpenSkyWorld",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState"
    ]
)
targets += interface(
    "OpenSkyInventory",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState",
        "OpenSkyConditions"
    ]
)

targets += feature(
    "OpenSkyActors",
    dependencies: ["OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState"],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyBehavior",
        "OpenSkyWorldState", "OpenSkyConditions"
    ],
    tests: [
        "FeaturesTesting", "OpenSkyActorsInterface", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyFactions",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyActorsInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface"
    ],
    tests: [
        "FeaturesTesting", "FormatsTesting", "OpenSkyActorsInterface", "OpenSkyFactionsFixtures",
        "OpenSkyFactionsInterface", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyProgression",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface"
    ],
    tests: [
        "OpenSkyActorsInterface", "FeaturesTesting", "OpenSkyConditions", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyProgressionFixtures", "OpenSkyProgressionInterface",
        "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyPerception",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyPhysics", "OpenSkyDiagnostics",
        "OpenSkyConditions"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyWorldState", "OpenSkyConditions"
    ],
    tests: [
        "FeaturesTesting", "OpenSkyDiagnostics", "OpenSkyFormatsESM", "OpenSkyPerceptionInterface",
        "OpenSkyPhysics",
        "OpenSkyShaderTypes"
    ]
)
targets += feature(
    "OpenSkyMagic",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyPhysics", "OpenSkyActorsInterface",
        "OpenSkyProgressionInterface", "OpenSkyInventoryInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyPhysics", "OpenSkyActorsInterface",
        "OpenSkyInventoryInterface"
    ],
    tests: [
        "OpenSkyActorsInterface", "FeaturesTesting", "OpenSkyConditions", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagicFixtures",
        "OpenSkyMagicInterface", "OpenSkyPhysics", "OpenSkyProgressionInterface",
        "OpenSkyWorldState"
    ]
)

targets += feature(
    "OpenSkyCrime",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface", "OpenSkyFactionsInterface",
        "OpenSkyInventoryInterface", "OpenSkyPerceptionInterface", "OpenSkyWorldInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface", "OpenSkyFactionsInterface",
        "OpenSkyInventoryInterface"
    ],
    tests: [
        "FeaturesTesting", "FormatsTesting", "OpenSkyActorsInterface", "OpenSkyConditions",
        "OpenSkyCrimeFixtures", "OpenSkyCrimeInterface", "OpenSkyFactionsInterface",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyInventory",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyFactionsInterface", "OpenSkyCrimeInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyWorldInterface", "OpenSkyConditions"
    ],
    tests: [
        "FeaturesTesting", "FormatsTesting", "OpenSkyConditions", "OpenSkyCrimeInterface",
        "OpenSkyFactionsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyCombat",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAnimation", "OpenSkyGameData",
        "OpenSkyBehavior", "OpenSkyPhysics", "OpenSkyAudio", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyPerceptionInterface", "OpenSkyProgressionInterface",
        "OpenSkyWorldInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyActorsInterface"
    ],
    tests: [
        "FormatsTesting", "OpenSkyActorsInterface", "OpenSkyBehavior", "OpenSkyCombatFixtures",
        "OpenSkyCombatInterface", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyPerceptionInterface",
        "OpenSkyPhysics", "OpenSkyProgressionInterface", "OpenSkyWorldState", "EngineTesting"
    ]
)
targets += feature(
    "OpenSkyQuests",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions"
    ],
    tests: [
        "FeaturesTesting", "FormatsTesting", "EngineTesting", "OpenSkyConditions",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyQuestsInterface",
        "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyDialogue",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAudio", "OpenSkyGameData",
        "OpenSkyWorldState", "OpenSkyConditions", "OpenSkyQuestsInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyQuestsInterface"
    ],
    tests: [
        "FormatsTesting", "EngineTesting", "OpenSkyConditions", "OpenSkyDialogueFixtures",
        "OpenSkyDialogueInterface", "FeaturesTesting", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyQuestsInterface", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyScripting",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsPEX", "OpenSkyGameData",
        "OpenSkyWorldState", "OpenSkyConditions", "OpenSkyPhysics", "OpenSkyActorsInterface",
        "OpenSkyCombatInterface", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyPerceptionInterface", "OpenSkyProgressionInterface", "OpenSkyQuestsInterface",
        "OpenSkyWorldInterface", "DequeModule"
    ],
    interface: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyWorldState"],
    swiftSettings: optimizedInDebug,
    tests: [
        "FormatsTesting", "OpenSkyConditions", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsPEX", "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyPhysics",
        "FeaturesTesting", "OpenSkyScriptingFixtures", "OpenSkyScriptingInterface",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

// Fakes of the feature interfaces, one library for every feature's tests. It depends
// on interfaces only, so a test that links it builds no feature but its own.
targets += testing(
    "FeaturesTesting",
    dependencies: [
        "FormatsTesting", "EngineTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyAudio", "OpenSkyPhysics", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyWorldInterface", "OpenSkyInventoryInterface",
        "OpenSkyActorsInterface", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyPerceptionInterface", "OpenSkyQuestsInterface"
    ]
)

targets += feature(
    "OpenSkyWorld",
    dependencies: ["OpenSkyFormatsCore"] + formatFamilies.map { "OpenSkyFormats\($0)" } + [
        "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyDiagnostics", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyAudio", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyActorsInterface", "OpenSkyFactionsInterface", "OpenSkyPerceptionInterface",
        "OpenSkyProgressionInterface", "OpenSkyCrimeInterface", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyCombatInterface", "OpenSkyQuestsInterface",
        "OpenSkyDialogueInterface", "OpenSkyScriptingInterface", "OpenSkyShaderTypes",
        "OpenSkyAssetCache", "OpenSkyImageKernels", "HeapModule"
    ],
    tests: [
        "EngineTesting", "FormatsTesting", "OpenSkyActorsInterface", "OpenSkyAudio",
        "OpenSkyImageKernels",
        "OpenSkyBehavior", "OpenSkyConditions", "OpenSkyCrimeInterface", "FeaturesTesting",
        "OpenSkyDiagnostics", "OpenSkyDialogueInterface", "OpenSkyFactionsInterface",
        "OpenSkyFormatsAnimation", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyFormatsSWF", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyPerceptionInterface",
        "OpenSkyPhysics", "OpenSkyProgressionInterface", "OpenSkyQuestsInterface",
        "OpenSkyRendering", "OpenSkyScriptingInterface", "OpenSkyShaderTypes",
        "OpenSkyWorldFixtures", "OpenSkyWorldInterface", "OpenSkyWorldState",
        "OpenSkyAssetCache"
    ]
)

targets += feature(
    "OpenSkySave",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsESS", "OpenSkyFormatsPEX",
        "OpenSkyGameData",
        "OpenSkyWorldState",
        "OpenSkyActorsInterface", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkyScriptingInterface",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "FormatsTesting", "OpenSkyActorsInterface", "OpenSkyCrimeInterface",
        "OpenSkyWorldInterface", "OpenSkyFactionsInterface", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsESS", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyDialogueInterface", "OpenSkyMagicInterface", "OpenSkyProgressionInterface",
        "OpenSkyQuestsInterface", "OpenSkySaveFixtures", "OpenSkyScriptingInterface",
        "OpenSkyWorldState", "EngineTesting"
    ]
)

targets += feature(
    "OpenSkyMenus",
    dependencies: [
        "OpenSkyConditions", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsSWF",
        "OpenSkyGameData", "OpenSkyRendering", "OpenSkyActorsInterface",
        "OpenSkyDialogueInterface", "OpenSkyInventoryInterface", "OpenSkyQuestsInterface",
        "OpenSkyScriptingInterface", "OpenSkyWorldInterface"
    ],
    tests: [
        "FormatsTesting", "OpenSkyActorsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyQuestsInterface", "OpenSkyRendering",
        "OpenSkyScriptingInterface", "OpenSkyShaderTypes", "OpenSkyWorldInterface",
        "EngineTesting"
    ]
)

// Fixtures that build one feature's implementation, for that feature's tests and the
// Xcode test bundles. Declared after every testing library they use.
targets += fixtures(
    "OpenSkyCombat",
    dependencies: [
        "OpenSkyActorsInterface", "OpenSkyBehavior", "OpenSkyCombat", "OpenSkyCombatInterface",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyMagicInterface",
        "OpenSkyPhysics", "OpenSkyProgressionInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyCrime",
    dependencies: [
        "OpenSkyCrime", "OpenSkyCrimeInterface", "FeaturesTesting", "OpenSkyFormatsESM",
        "OpenSkyInventoryInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyDialogue",
    dependencies: [
        "OpenSkyConditions", "OpenSkyDialogue", "OpenSkyDialogueInterface",
        "FeaturesTesting", "OpenSkyQuestsInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyFactions",
    dependencies: [
        "OpenSkyFactions", "FeaturesTesting", "OpenSkyGameData"
    ]
)
targets += fixtures(
    "OpenSkyMagic",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagic",
        "OpenSkyMagicInterface", "FeaturesTesting", "OpenSkyProgressionInterface",
        "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyProgression",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyProgression"
    ]
)
targets += fixtures(
    "OpenSkySave",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkySave",
        "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyScripting",
    dependencies: [
        "FormatsTesting", "OpenSkyFormatsESM", "OpenSkyFormatsPEX", "OpenSkyGameData",
        "OpenSkyScripting", "OpenSkyScriptingInterface", "OpenSkyWorldInterface",
        "OpenSkyWorldState", "FeaturesTesting"
    ]
)
targets += fixtures(
    "OpenSkyWorld",
    dependencies: [
        "FormatsTesting", "OpenSkyAudio", "OpenSkyConditions", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyWorld", "OpenSkyWorldInterface", "OpenSkyWorldState",
        "FeaturesTesting", "EngineTesting"
    ]
)

// Composition: code the app and OpenSkyCLI share.
targets += composition(
    "OpenSkyPreview",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsAnimation", "OpenSkyGameData", "OpenSkyConditions", "OpenSkyRendering",
        "OpenSkyWorld"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "FormatsTesting", "EngineTesting"
    ]
)

// The openskycli command line (docs/tools/modules.md): nonisolated, linked by the CLI only.
targets.append(.target(
    name: "OpenSkyCLIArguments", dependencies: checked("OpenSkyCLIArguments", ["ArgumentParser"]),
    swiftSettings: languageSettings
))
deferTests("OpenSkyCLIArgumentsTests", dependencies: ["OpenSkyCLIArguments"])

targets += deferredTests

let package = Package(
    name: "OpenSky",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "OpenSkyModules",
            targets: ["OpenSkyShaderTypes", "CASTCEncoder"] + libraryTargets
        ),
        .library(name: "OpenSkyTestSupport", targets: testingTargets + fixtureTargets),
        .library(name: "OpenSkyCLIArguments", targets: ["OpenSkyCLIArguments"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0")
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
