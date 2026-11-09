// swift-tools-version: 6.2
// The engine, one module per layer, by The Modular Architecture
// (docs/tools/modules.md). Modules are declared bottom-up: a module depends only
// on earlier ones, and a feature depends on another feature's interface only.
// The helpers below stop the manifest from loading when a rule breaks.

import PackageDescription

/// The same language settings as config/Build/Base.xcconfig. Change both together.
let languageSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error)
]

/// The vendored decode-only ffmpeg (make bootstrap). Its headers are on every module's
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
        dependencies: dependencies.map { .target(name: $0) },
        swiftSettings: testSettings,
        linkerSettings: testLinkerSettings
    )
}

/// Test targets wait until every library is declared, because a test may link a
/// testing library that sits above the module under test (`OpenSkyEngineTesting` over
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

/// A domain of the world feature: a module below `OpenSkyWorld` that may use lower
/// modules, feature interfaces, and earlier domains. Only the world feature, later
/// domains, and the composition roots may depend on one (module-graph rule 9).
func domain(_ name: String, dependencies: [String], tests: [String]) -> [Target] {
    foundation(name, dependencies: dependencies, tests: tests)
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

/// The structs shared with Metal. The shaders in Sources/OpenSkyShaders include the same header.
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
/// The vendored astcenc (make bootstrap), a static library behind a C shim. Like
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

// The Swift Testing tags a test target links when it tags its tests.
targets += testing("OpenSkyTagsTesting", dependencies: [])

// Foundation

// Formats: a core of binary readers, compression, geometry values, archives and
// string tables, then one module per format family. A family depends only on the
// core, so a parser change rebuilds one family and the modules that use it.
targets += foundation("OpenSkyFormatsCore", tests: ["OpenSkyTagsTesting", "OpenSkyFormatsTesting"])
/// CPU loops such as the chargen face paint and the Papyrus interpreter run up to 100
/// times slower unoptimized, so Debug builds them optimized too.
let optimizedInDebug: [SwiftSetting] = [.unsafeFlags(["-O"], .when(configuration: .debug))]
targets += foundation("OpenSkyImageKernels", swiftSettings: optimizedInDebug)
// The Metal shaders: SwiftPM compiles the `.metal` files into the bundle's `default.metallib`.
targets += foundation("OpenSkyShaders", tests: ["OpenSkyTagsTesting"])
let formatFamilies = ["ESM", "Mesh", "Animation", "Audio", "PEX", "SWF", "ESS"]
for family in formatFamilies {
    let module = "OpenSkyFormats\(family)"
    let kernels = family == "Mesh" ? ["OpenSkyImageKernels"] : []
    // The Audio and PEX tests reach the core only through the testing library.
    let core = ["Audio", "PEX"].contains(family) ? [] : ["OpenSkyFormatsCore"]
    targets += foundation(
        module,
        dependencies: ["OpenSkyFormatsCore"] + kernels,
        tests: ["OpenSkyTagsTesting", "OpenSkyFormatsTesting"] + core + kernels
    )
}

// Byte builders and fixtures for every format family in one library, so a parser
// test links one target. The families stay apart in Sources/.
targets += testing(
    "OpenSkyFormatsTesting",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsAnimation", "OpenSkyFormatsPEX", "OpenSkyFormatsSWF"
    ]
)

targets += foundation(
    "OpenSkyGameData",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsTesting", "OpenSkyEngineTesting"
    ]
)
targets += foundation(
    "OpenSkyBehavior",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "OpenSkyGameData"],
    tests: [
        "OpenSkyEngineTesting", "OpenSkyFormatsCore", "OpenSkyFormatsAnimation",
        "OpenSkyFormatsTesting",
        "OpenSkyFormatsMesh", "OpenSkyGameData"
    ]
)

// The asset cache folder: entries, staleness, and the size limit. Loaders above
// it read converted assets from it (docs/engine/asset-cache.md). Each format's
// converter and decoder live with the module that owns the format.
targets += foundation(
    "OpenSkyAssetCache",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyGameData"],
    tests: ["OpenSkyFormatsCore", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyFormatsTesting"]
)
targets += foundation(
    "OpenSkyLaunch",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"],
    tests: ["OpenSkyFormatsCore", "OpenSkyGameData", "OpenSkyFormatsTesting"]
)
// The Windows reference game: its prefix, launch, batch file, and version check
// (docs/tools/reference-game.md). Developer tooling; the app shows it only once set up.
targets += foundation(
    "OpenSkyReference",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyGameData"],
    tests: []
)
targets += foundation("OpenSkyDiagnostics", dependencies: [])
// The agent control protocol, socket, and router; the app and openskycli both link it.
targets += foundation("OpenSkyAgentControl", dependencies: ["OpenSkyFormatsCore"], tests: [])
targets += foundation(
    "OpenSkyPhysics",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsAnimation",
        "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyAssetCache"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsTesting", "OpenSkyGameData"
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
        "OpenSkyFormatsTesting", "OpenSkyAssetCache"
    ]
)

// Rendering: a Metal-free core and the GPU resources below the renderer, so a change
// to a pass does not rebuild terrain meshes or texture loading.
targets += foundation(
    "OpenSkyRenderCore",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyShaderTypes"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF",
        "OpenSkyFormatsTesting", "OpenSkyShaderTypes", "OpenSkyEngineTesting"
    ]
)
targets += foundation(
    "OpenSkyRenderResources",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyShaderTypes",
        "OpenSkyAssetCache", "CASTCEncoder"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyAssetCache", "OpenSkyFormatsCore", "OpenSkyFormatsMesh",
        "OpenSkyFormatsTesting", "OpenSkyGameData", "OpenSkyShaderTypes",
        "OpenSkyEngineTesting"
    ]
)
targets += foundation(
    "OpenSkyRendering",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF",
        "OpenSkyGameData", "OpenSkyShaderTypes", "OpenSkyShaders", "OpenSkyAssetCache",
        "OpenSkyRenderCore", "OpenSkyRenderResources"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyGameData", "OpenSkyShaderTypes", "OpenSkyFormatsTesting",
        "OpenSkyEngineTesting", "OpenSkyRenderCore", "OpenSkyRenderResources", "OpenSkyFormatsSWF"
    ]
)

targets += foundation(
    "OpenSkyWorldState",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyFormatsTesting",
        "OpenSkyEngineTesting", "OpenSkyRenderCore"
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
    "OpenSkyEngineTesting",
    dependencies: [
        "OpenSkyFormatsTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsAnimation",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyWorldState", "OpenSkyRenderCore", "OpenSkyFormatsSWF",
        "OpenSkyShaders"
    ]
)

// Features

// Every interface is declared ahead of the features, because a feature needs the
// values of interfaces whose implementations come later.
targets += interface(
    "OpenSkyActors",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyBehavior",
        "OpenSkyWorldState",
        "OpenSkyConditions"
    ]
)
targets += interface(
    "OpenSkyPerception",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyPhysics", "OpenSkyConditions"
    ]
)
targets += interface(
    "OpenSkyFactions",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyActorsInterface"
    ]
)
targets += interface(
    "OpenSkyProgression",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyActorsInterface"
    ]
)
targets += interface(
    "OpenSkyWorld",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyBehavior", "OpenSkyConditions", "OpenSkyFormatsAnimation", "OpenSkyFormatsMesh",
        "OpenSkyPhysics", "OpenSkyRenderCore", "OpenSkyShaderTypes"
    ]
)
targets += interface(
    "OpenSkyInventory",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState",
        "OpenSkyConditions",
        "OpenSkyFactionsInterface",
        "OpenSkyProgressionInterface",
        "OpenSkyWorldInterface"
    ]
)
targets += interface(
    "OpenSkyMagic",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyPhysics", "OpenSkyInventoryInterface",
        "OpenSkyProgressionInterface"
    ]
)
targets += interface(
    "OpenSkyCombat",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyPhysics",
        "OpenSkyActorsInterface",
        "OpenSkyAudio",
        "OpenSkyBehavior",
        "OpenSkyFormatsMesh",
        "OpenSkyPerceptionInterface",
        "OpenSkyWorldState",
        "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface"
    ]
)
targets += interface(
    "OpenSkyCrime",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyWorldInterface"
    ]
)
targets += interface(
    "OpenSkyQuests",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState",
        "OpenSkyConditions"
    ]
)
targets += interface(
    "OpenSkyDialogue",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions"
    ]
)
targets += interface(
    "OpenSkyMenus",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyAudio",
        "OpenSkyConditions", "OpenSkyFormatsAudio", "OpenSkyFormatsSWF", "OpenSkyRendering",
        "OpenSkyWorldInterface", "OpenSkyRenderCore"
    ]
)
targets += interface(
    "OpenSkyScripting",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyGameData", "OpenSkyFormatsPEX", "OpenSkyFactionsInterface",
        "OpenSkyInventoryInterface", "OpenSkyPerceptionInterface", "OpenSkyWorldInterface"
    ]
)
targets += interface(
    "OpenSkySave",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState",
        "OpenSkyScriptingInterface"
    ]
)

targets += feature(
    "OpenSkyActors",
    dependencies: ["OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState"],
    tests: [
        "OpenSkyActorsInterface", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyFactions",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyActorsInterface"
    ],
    tests: [
        "OpenSkyFeaturesTesting", "OpenSkyFormatsTesting", "OpenSkyActorsInterface",
        "OpenSkyConditions", "OpenSkyFactionsFixtures",
        "OpenSkyFactionsInterface", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyProgression",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface"
    ],
    tests: [
        "OpenSkyActorsInterface", "OpenSkyEngineTesting", "OpenSkyFeaturesTesting",
        "OpenSkyFormatsTesting", "OpenSkyConditions", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyProgressionFixtures", "OpenSkyProgressionInterface",
        "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyPerception",
    dependencies: ["OpenSkyFormatsESM", "OpenSkyPhysics", "OpenSkyRenderCore"],
    tests: [
        "OpenSkyFeaturesTesting", "OpenSkyFormatsESM", "OpenSkyPerceptionInterface",
        "OpenSkyPhysics", "OpenSkyShaderTypes", "OpenSkyRenderCore"
    ]
)
targets += feature(
    "OpenSkyMagic",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyPhysics", "OpenSkyActorsInterface",
        "OpenSkyProgressionInterface", "OpenSkyInventoryInterface"
    ],
    tests: [
        "OpenSkyActorsInterface", "OpenSkyFeaturesTesting", "OpenSkyFormatsTesting",
        "OpenSkyConditions", "OpenSkyFormatsESM",
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
    tests: [
        "OpenSkyFeaturesTesting", "OpenSkyFormatsTesting", "OpenSkyEngineTesting",
        "OpenSkyActorsInterface", "OpenSkyConditions",
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
        "OpenSkyFeaturesTesting", "OpenSkyFormatsTesting", "OpenSkyEngineTesting",
        "OpenSkyConditions", "OpenSkyCrimeInterface",
        "OpenSkyFactionsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)
targets += feature(
    "OpenSkyCombat",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAnimation", "OpenSkyFormatsMesh",
        "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics", "OpenSkyAudio", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyActorsInterface", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyPerceptionInterface", "OpenSkyProgressionInterface",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyFormatsTesting", "OpenSkyActorsInterface", "OpenSkyBehavior",
        "OpenSkyCombatFixtures", "OpenSkyConditions",
        "OpenSkyCombatInterface", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyPerceptionInterface",
        "OpenSkyPhysics", "OpenSkyProgressionInterface", "OpenSkyWorldState", "OpenSkyEngineTesting"
    ]
)
targets += feature(
    "OpenSkyQuests",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions"
    ],
    tests: [
        "OpenSkyFormatsTesting", "OpenSkyEngineTesting", "OpenSkyConditions",
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
    tests: [
        "OpenSkyFormatsTesting", "OpenSkyEngineTesting", "OpenSkyConditions",
        "OpenSkyDialogueFixtures",
        "OpenSkyDialogueInterface", "OpenSkyFeaturesTesting", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
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
        "OpenSkyPerceptionInterface", "OpenSkyQuestsInterface", "OpenSkyWorldInterface",
        "DequeModule"
    ],
    swiftSettings: optimizedInDebug,
    tests: [
        "OpenSkyFormatsTesting", "OpenSkyActorsInterface", "OpenSkyCombatInterface",
        "OpenSkyConditions", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsPEX", "OpenSkyGameData",
        "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyPerceptionInterface", "OpenSkyPhysics",
        "OpenSkyFeaturesTesting",
        "OpenSkyScriptingFixtures",
        "OpenSkyScriptingInterface", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

// Fakes of the feature interfaces, one library for every feature's tests. It depends
// on interfaces only, so a test that links it builds no feature but its own.
targets += testing(
    "OpenSkyFeaturesTesting",
    dependencies: [
        "OpenSkyFormatsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyAudio", "OpenSkyPhysics", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyWorldInterface", "OpenSkyInventoryInterface",
        "OpenSkyActorsInterface", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyPerceptionInterface", "OpenSkyQuestsInterface"
    ]
)

// The domains of the world feature, lowest first (docs/tools/modules.md).
targets += domain(
    "OpenSkyWorldConditionFunctions",
    dependencies: ["OpenSkyFormatsESM", "OpenSkyConditions", "OpenSkyWorldInterface"],
    tests: [
        "OpenSkyFeaturesTesting", "OpenSkyConditions", "OpenSkyFormatsESM",
        "OpenSkyWorldInterface"
    ]
)
targets += domain(
    "OpenSkyWeather",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "OpenSkyShaderTypes", "OpenSkyWorldState", "OpenSkyRenderCore",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyEngineTesting", "OpenSkyFormatsTesting", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyRenderCore"
    ]
)
targets += domain(
    "OpenSkyNavigation",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyWorldInterface", "HeapModule", "OpenSkyRenderCore"
    ],
    tests: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"]
)
targets += domain(
    "OpenSkyTerrain",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyRendering",
        "OpenSkyAssetCache", "OpenSkyImageKernels", "OpenSkyRenderCore", "OpenSkyRenderResources"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsTesting",
        "OpenSkyImageKernels", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyGameData", "OpenSkyRendering", "OpenSkyRenderCore", "OpenSkyRenderResources",
        "OpenSkyNavigation"
    ]
)
targets += domain(
    "OpenSkyEffects",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyAudio", "OpenSkyRendering", "OpenSkyShaderTypes", "OpenSkyMagicInterface",
        "OpenSkyRenderCore",
        "OpenSkyRenderResources",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyFormatsTesting", "OpenSkyAudio", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyMagicInterface", "OpenSkyRendering", "OpenSkyWorldInterface",
        "OpenSkyRenderCore"
    ]
)
targets += domain(
    "OpenSkyCamera",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyConditions",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyFormatsTesting", "OpenSkyConditions", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyWorldInterface",
        "OpenSkyWorldConditions"
    ]
)
targets += domain(
    "OpenSkyRuntimeState",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyAudio",
        "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyEngineTesting", "OpenSkyFormatsTesting", "OpenSkyFeaturesTesting",
        "OpenSkyWorldTesting", "OpenSkyActorsInterface", "OpenSkyConditions",
        "OpenSkyCrimeInterface", "OpenSkyDialogueInterface", "OpenSkyFactionsInterface",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyPhysics",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkyScriptingInterface",
        "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyWorldConditions"
    ]
)
targets += domain(
    "OpenSkyActorPresentation",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsAnimation", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics",
        "OpenSkyAudio", "OpenSkyRendering", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyWorldInterface", "OpenSkyCombatInterface", "OpenSkyWorldConditionFunctions",
        "OpenSkyRuntimeState", "OpenSkyRenderCore", "OpenSkyRenderResources"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsTesting",
        "OpenSkyWorldTesting", "OpenSkyAudio", "OpenSkyImageKernels", "OpenSkyBehavior",
        "OpenSkyConditions", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyNavigation", "OpenSkyRuntimeState"
    ]
)
targets += domain(
    "OpenSkyPlayer",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsAnimation", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyWorldInterface", "OpenSkyCombatInterface",
        "OpenSkyRenderCore", "OpenSkyRenderResources"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsTesting",
        "OpenSkyBehavior", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyWorldInterface", "OpenSkyRenderCore",
        "OpenSkyRenderResources"
    ]
)
targets += domain(
    "OpenSkyObjectAnimation",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyActorPresentation",
        "OpenSkyEffects", "OpenSkyRendering", "OpenSkyRenderCore", "OpenSkyWorldInterface",
        "OpenSkyPlayer"
    ],
    tests: [
        "OpenSkyEngineTesting", "OpenSkyFormatsTesting", "OpenSkyBehavior",
        "OpenSkyFormatsAnimation", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyWorldInterface", "OpenSkyActorPresentation"
    ]
)
targets += domain(
    "OpenSkyAIPackages",
    dependencies: [
        "OpenSkyConditions", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyPhysics", "OpenSkyPlayer", "OpenSkyRenderCore", "OpenSkyWorldConditionFunctions",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
    ],
    tests: [
        "OpenSkyEngineTesting", "OpenSkyFormatsTesting", "OpenSkyFeaturesTesting",
        "OpenSkyWorldTesting", "OpenSkyConditions", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyPhysics",
        "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyRenderCore", "OpenSkyNavigation",
        "OpenSkyPlayer", "OpenSkyWorldConditions"
    ]
)
targets += domain(
    "OpenSkyCells",
    dependencies: [
        "OpenSkyActorsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyFormatsAnimation", "OpenSkyImageKernels",
        "OpenSkyGameData", "OpenSkyAssetCache", "OpenSkyPhysics", "OpenSkyAudio",
        "OpenSkyRendering", "OpenSkyShaderTypes", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyWorldInterface", "OpenSkyCombatInterface", "OpenSkyCrimeInterface",
        "OpenSkyInventoryInterface", "OpenSkyPerceptionInterface", "OpenSkyWeather",
        "OpenSkyNavigation", "OpenSkyTerrain", "OpenSkyRuntimeState",
        "OpenSkyActorPresentation", "OpenSkyBehavior", "OpenSkyObjectAnimation",
        "OpenSkyPlayer", "OpenSkyAIPackages", "OpenSkyRenderCore", "OpenSkyRenderResources"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsTesting",
        "OpenSkyWorldTesting", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyPhysics", "OpenSkyRendering",
        "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyNavigation", "OpenSkyTerrain",
        "OpenSkyActorPresentation", "OpenSkyObjectAnimation", "OpenSkyPlayer",
        "OpenSkyAIPackages"
    ]
)
// The whole-game condition set: every feature's functions in one registry. It
// names every feature, so it sits high; the modules below take a registry instead.
targets += domain(
    "OpenSkyWorldConditions",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyActorsInterface", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyPerceptionInterface", "OpenSkyProgressionInterface", "OpenSkyQuestsInterface",
        "OpenSkyScriptingInterface", "OpenSkyWorldConditionFunctions", "OpenSkyGameData"
    ],
    tests: [
        "OpenSkyEngineTesting", "OpenSkyFormatsTesting", "OpenSkyFeaturesTesting",
        "OpenSkyWorldTesting", "OpenSkyActorsInterface", "OpenSkyConditions",
        "OpenSkyCrimeInterface", "OpenSkyDialogueInterface", "OpenSkyFactionsInterface",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyPerceptionInterface", "OpenSkyQuestsInterface",
        "OpenSkyScriptingInterface", "OpenSkyWorldState", "OpenSkyWorldConditionFunctions"
    ]
)
targets += domain(
    "OpenSkyLoading",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyAssetCache",
        "OpenSkyConditions", "OpenSkyWorldConditions", "OpenSkyCells", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyEngineTesting", "OpenSkyFormatsTesting",
        "OpenSkyConditions", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyPhysics",
        "OpenSkyWorldInterface", "OpenSkyAssetCache", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyPlayer", "OpenSkyCells"
    ]
)
// Fixtures over the world domains below OpenSkyWorld: cell scenes, actor visuals,
// and the standard condition registry.
targets += testing(
    "OpenSkyWorldTesting",
    dependencies: [
        "OpenSkyFormatsTesting", "OpenSkyFeaturesTesting", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyAudio", "OpenSkyWorldConditions", "OpenSkyTerrain",
        "OpenSkyRuntimeState", "OpenSkyActorPresentation", "OpenSkyCells",
        "OpenSkyRenderResources"
    ]
)

targets += feature(
    "OpenSkyWorld",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAnimation",
        "OpenSkyGameData", "OpenSkyDiagnostics", "OpenSkyPhysics", "OpenSkyRendering",
        "OpenSkyAudio", "OpenSkyWorldState", "OpenSkyActorsInterface",
        "OpenSkyInventoryInterface", "OpenSkyAssetCache", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyWeather", "OpenSkyNavigation", "OpenSkyTerrain",
        "OpenSkyCamera", "OpenSkyRuntimeState", "OpenSkyActorPresentation",
        "OpenSkyObjectAnimation", "OpenSkyPlayer", "OpenSkyAIPackages", "OpenSkyCells",
        "OpenSkyLoading"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyWorldConditions", "OpenSkyWeather", "OpenSkyNavigation",
        "OpenSkyTerrain", "OpenSkyRuntimeState", "OpenSkyActorPresentation", "OpenSkyPlayer",
        "OpenSkyAIPackages", "OpenSkyCells", "OpenSkyRenderCore", "OpenSkyRenderResources",
        "OpenSkyWorldTesting", "OpenSkyEngineTesting", "OpenSkyFormatsTesting", "OpenSkyAudio",
        "OpenSkyConditions", "OpenSkyFeaturesTesting", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyPhysics", "OpenSkyRendering",
        "OpenSkyShaderTypes", "OpenSkyWorldFixtures", "OpenSkyWorldInterface",
        "OpenSkyWorldState", "OpenSkyAssetCache"
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
        "OpenSkyFormatsTesting", "OpenSkyActorsInterface", "OpenSkyCrimeInterface",
        "OpenSkyWorldInterface", "OpenSkyFactionsInterface", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsESS", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyDialogueInterface", "OpenSkyMagicInterface", "OpenSkyProgressionInterface",
        "OpenSkyQuestsInterface", "OpenSkySaveFixtures", "OpenSkyScriptingInterface",
        "OpenSkyWorldState", "OpenSkyEngineTesting",
        "OpenSkySaveInterface"
    ]
)

targets += feature(
    "OpenSkyMenus",
    dependencies: [
        "OpenSkyAudio", "OpenSkyFormatsAudio", "OpenSkyConditions", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyRendering", "OpenSkyActorsInterface",
        "OpenSkyDialogueInterface", "OpenSkyInventoryInterface", "OpenSkyProgressionInterface",
        "OpenSkyQuestsInterface", "OpenSkyScriptingInterface", "OpenSkyWorldInterface",
        "OpenSkyRenderCore",
        "OpenSkyRenderResources",
        "OpenSkyWorldState"
    ],
    tests: [
        "OpenSkyTagsTesting", "OpenSkyAudio", "OpenSkyFormatsTesting",
        "OpenSkyActorsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyInventoryInterface", "OpenSkyProgressionInterface",
        "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyQuestsInterface", "OpenSkyRendering",
        "OpenSkyScriptingInterface", "OpenSkyShaderTypes", "OpenSkyWorldInterface",
        "OpenSkyEngineTesting", "OpenSkyRenderCore", "OpenSkyMenusInterface",
        "OpenSkyWorldState"
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
        "OpenSkyCrime", "OpenSkyCrimeInterface", "OpenSkyFeaturesTesting", "OpenSkyFormatsESM",
        "OpenSkyInventoryInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyDialogue",
    dependencies: [
        "OpenSkyConditions", "OpenSkyDialogue", "OpenSkyDialogueInterface",
        "OpenSkyFeaturesTesting", "OpenSkyQuestsInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyFactions",
    dependencies: [
        "OpenSkyFactions", "OpenSkyFeaturesTesting", "OpenSkyGameData",
        "OpenSkyFactionsInterface"
    ]
)
targets += fixtures(
    "OpenSkyMagic",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagic",
        "OpenSkyMagicInterface", "OpenSkyFeaturesTesting", "OpenSkyPhysics",
        "OpenSkyProgressionInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyProgression",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyProgression",
        "OpenSkyProgressionInterface"
    ]
)
targets += fixtures(
    "OpenSkySave",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkySave",
        "OpenSkyWorldState",
        "OpenSkySaveInterface"
    ]
)
targets += fixtures(
    "OpenSkyScripting",
    dependencies: [
        "OpenSkyFormatsTesting", "OpenSkyFormatsESM", "OpenSkyFormatsPEX", "OpenSkyGameData",
        "OpenSkyScripting", "OpenSkyScriptingInterface", "OpenSkyWorldInterface",
        "OpenSkyWorldState", "OpenSkyFeaturesTesting"
    ]
)
targets += fixtures(
    "OpenSkyWorld",
    dependencies: [
        "OpenSkyFormatsTesting", "OpenSkyAudio", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyPhysics", "OpenSkyRendering",
        "OpenSkyWorld", "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyEngineTesting",
        "OpenSkyWorldTesting", "OpenSkyRenderResources", "OpenSkyTerrain", "OpenSkyCells",
        "OpenSkyRenderCore"
    ]
)

// Composition: code the app and OpenSkyCLI share.
// The ports through which the session's adapters reach each feature, and the
// conformances of the feature types to them (docs/decisions/ports-and-adapters.md).
targets += interface(
    "OpenSkySession",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAnimation",
        "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics", "OpenSkyAgentControl",
        "OpenSkyRenderCore", "OpenSkyAudio", "OpenSkyWorldState", "OpenSkyConditions",
        "OpenSkyActorsInterface", "OpenSkyCombatInterface", "OpenSkyCrimeInterface",
        "OpenSkyDialogueInterface", "OpenSkyFactionsInterface", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyMenusInterface", "OpenSkyPerceptionInterface",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkySaveInterface",
        "OpenSkyScriptingInterface", "OpenSkyWorldInterface", "OpenSkyRendering",
        "OpenSkyRenderResources"
    ]
)
targets += composition(
    "OpenSkySession",
    dependencies: [
        "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyRenderCore", "OpenSkyRendering",
        "OpenSkyWorldState", "OpenSkySessionInterface", "OpenSkyActors", "OpenSkyCombat",
        "OpenSkyCrime", "OpenSkyDialogue", "OpenSkyFactions", "OpenSkyInventory",
        "OpenSkyMagic", "OpenSkyMenus", "OpenSkyPerception", "OpenSkyProgression",
        "OpenSkyQuests", "OpenSkyScripting", "OpenSkyWorld", "OpenSkyQuestsInterface",
        "OpenSkyInventoryInterface", "OpenSkyWorldInterface", "OpenSkyWeather",
        "OpenSkyTerrain", "OpenSkyEffects", "OpenSkyCamera", "OpenSkyRuntimeState",
        "OpenSkyActorPresentation", "OpenSkyObjectAnimation", "OpenSkyPlayer",
        "OpenSkyAIPackages", "OpenSkyCells", "OpenSkyLoading", "OpenSkyAssetCache",
        "OpenSkyPhysics", "OpenSkyRenderResources", "OpenSkyShaders"
    ]
)

targets += composition(
    "OpenSkyPreview",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyConditions", "OpenSkyRendering", "OpenSkyWorld", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyReference", "OpenSkyWorldInterface",
        "OpenSkyWorldConditions", "OpenSkyWeather", "OpenSkyTerrain", "OpenSkyRuntimeState",
        "OpenSkyCells"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "OpenSkyFormatsTesting", "OpenSkyEngineTesting", "OpenSkyRenderCore"
    ]
)

// The world adapters (docs/decisions/ports-and-adapters.md): each answers one feature's
// world port from the session. Only the app and openskycli link them.
targets += composition(
    "OpenSkyAIAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyActors",
        "OpenSkyActorsInterface", "OpenSkyCells", "OpenSkyCombat", "OpenSkyCombatInterface",
        "OpenSkyConditions", "OpenSkyCrime", "OpenSkyCrimeInterface", "OpenSkyDialogue",
        "OpenSkyDialogueInterface", "OpenSkyFactions", "OpenSkyFormatsAnimation",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyInventory", "OpenSkyInventoryInterface", "OpenSkyMagic",
        "OpenSkyMagicInterface", "OpenSkyNavigation", "OpenSkyPerception",
        "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyPlayer", "OpenSkyProgression",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkyRenderCore",
        "OpenSkyRendering", "OpenSkyRuntimeState", "OpenSkyScripting",
        "OpenSkyScriptingInterface", "OpenSkySessionInterface", "OpenSkyWorld",
        "OpenSkyWorldConditions", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyActorAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyActors",
        "OpenSkyActorsInterface", "OpenSkyAudio", "OpenSkyBehavior", "OpenSkyCamera",
        "OpenSkyCells", "OpenSkyCombat", "OpenSkyCombatInterface", "OpenSkyConditions",
        "OpenSkyCrime", "OpenSkyCrimeInterface", "OpenSkyEffects", "OpenSkyFactions",
        "OpenSkyFactionsInterface", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyInventory",
        "OpenSkyInventoryInterface", "OpenSkyMagic", "OpenSkyMagicInterface", "OpenSkyMenus",
        "OpenSkyMenusInterface", "OpenSkyNavigation", "OpenSkyObjectAnimation",
        "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyPlayer", "OpenSkyProgression",
        "OpenSkyProgressionInterface", "OpenSkyQuests", "OpenSkyQuestsInterface",
        "OpenSkyRenderCore", "OpenSkyRendering", "OpenSkyRuntimeState", "OpenSkyScripting",
        "OpenSkyScriptingInterface", "OpenSkySession", "OpenSkySessionInterface",
        "OpenSkyTerrain", "OpenSkyWorld", "OpenSkyWorldInterface", "OpenSkyWorldState",
        "OpenSkyWorldConditions"
    ]
)

targets += composition(
    "OpenSkyAgentAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyActors",
        "OpenSkyActorsInterface", "OpenSkyAgentControl", "OpenSkyAudio", "OpenSkyBehavior",
        "OpenSkyCells", "OpenSkyCombat", "OpenSkyCombatInterface", "OpenSkyConditions",
        "OpenSkyCrimeInterface", "OpenSkyDiagnostics", "OpenSkyDialogue",
        "OpenSkyDialogueInterface", "OpenSkyEffects", "OpenSkyFactions",
        "OpenSkyFactionsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyInventory", "OpenSkyInventoryInterface",
        "OpenSkyLoading", "OpenSkyMagic", "OpenSkyMagicInterface", "OpenSkyMenus",
        "OpenSkyMenusInterface", "OpenSkyObjectAnimation", "OpenSkyPerception",
        "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyPlayer", "OpenSkyProgression",
        "OpenSkyProgressionInterface", "OpenSkyQuests", "OpenSkyQuestsInterface",
        "OpenSkyReference", "OpenSkyRenderCore", "OpenSkyRenderResources", "OpenSkyRendering",
        "OpenSkyRuntimeState", "OpenSkySave", "OpenSkySaveInterface", "OpenSkyScripting",
        "OpenSkyScriptingInterface", "OpenSkySession", "OpenSkySessionInterface",
        "OpenSkyWeather", "OpenSkyWorld", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyCombatAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyActors",
        "OpenSkyActorsInterface", "OpenSkyAudio", "OpenSkyBehavior", "OpenSkyCamera",
        "OpenSkyCells", "OpenSkyCombat", "OpenSkyCombatInterface", "OpenSkyConditions",
        "OpenSkyCrime", "OpenSkyDialogue", "OpenSkyDialogueInterface", "OpenSkyEffects",
        "OpenSkyFactions", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyGameData", "OpenSkyInventory", "OpenSkyInventoryInterface", "OpenSkyMagic",
        "OpenSkyMagicInterface", "OpenSkyMenus", "OpenSkyNavigation", "OpenSkyPerception",
        "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyPlayer", "OpenSkyProgression",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyRendering", "OpenSkyRuntimeState", "OpenSkyScripting",
        "OpenSkyScriptingInterface", "OpenSkySessionInterface", "OpenSkyWorld",
        "OpenSkyWorldConditions", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyInventoryAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyCells", "OpenSkyConditions", "OpenSkyCrimeInterface",
        "OpenSkyFactionsInterface", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventory",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyMenusInterface",
        "OpenSkyPerceptionInterface", "OpenSkyPlayer", "OpenSkyProgressionInterface",
        "OpenSkyRenderCore", "OpenSkyRendering", "OpenSkyRuntimeState",
        "OpenSkyScriptingInterface", "OpenSkySessionInterface", "OpenSkyWorldConditions",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyMagicAdapters",
    dependencies: [
        "OpenSkyActorsInterface", "OpenSkyBehavior", "OpenSkyCells", "OpenSkyCombatInterface",
        "OpenSkyConditions", "OpenSkyDialogueInterface", "OpenSkyEffects", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyMagic", "OpenSkyMagicInterface",
        "OpenSkyMenusInterface", "OpenSkyNavigation", "OpenSkyPhysics", "OpenSkyPlayer",
        "OpenSkyProgressionInterface", "OpenSkyRenderCore", "OpenSkyRendering",
        "OpenSkyRuntimeState", "OpenSkyScriptingInterface", "OpenSkySessionInterface",
        "OpenSkyWorld", "OpenSkyWorldConditions", "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyMenuAdapters",
    dependencies: [
        "OpenSkyActors", "OpenSkyActorsInterface", "OpenSkyAgentControl", "OpenSkyAudio",
        "OpenSkyCamera", "OpenSkyCells", "OpenSkyCombat", "OpenSkyCombatInterface",
        "OpenSkyConditions", "OpenSkyCrime", "OpenSkyCrimeInterface", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyInventory",
        "OpenSkyInventoryInterface", "OpenSkyLaunch", "OpenSkyLoading", "OpenSkyMagic",
        "OpenSkyMagicInterface", "OpenSkyMenus", "OpenSkyMenusInterface", "OpenSkyPhysics",
        "OpenSkyPlayer", "OpenSkyProgression", "OpenSkyProgressionInterface", "OpenSkyQuests",
        "OpenSkyQuestsInterface", "OpenSkyRenderCore", "OpenSkyRenderResources",
        "OpenSkyRendering", "OpenSkyRuntimeState", "OpenSkySave", "OpenSkySaveInterface",
        "OpenSkyScripting", "OpenSkyScriptingInterface", "OpenSkySession",
        "OpenSkySessionInterface", "OpenSkyTerrain", "OpenSkyWorld", "OpenSkyWorldConditions",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyProgressionAdapters",
    dependencies: [
        "OpenSkyAudio", "OpenSkyCells", "OpenSkyConditions", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface",
        "OpenSkyPlayer", "OpenSkyProgression", "OpenSkyProgressionInterface",
        "OpenSkyQuestsInterface",
        "OpenSkyRuntimeState", "OpenSkySessionInterface", "OpenSkyWorldConditions",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkyScriptAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyAgentControl", "OpenSkyCells",
        "OpenSkyCombatInterface", "OpenSkyConditions", "OpenSkyEffects", "OpenSkyFormatsAnimation",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyMagicInterface", "OpenSkyMenusInterface", "OpenSkyNavigation",
        "OpenSkyObjectAnimation", "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyPlayer",
        "OpenSkyQuestsInterface", "OpenSkyRenderCore", "OpenSkyRenderResources", "OpenSkyRendering",
        "OpenSkyRuntimeState", "OpenSkyScripting", "OpenSkyScriptingInterface",
        "OpenSkySessionInterface", "OpenSkyWeather", "OpenSkyWorld", "OpenSkyWorldInterface",
        "OpenSkyWorldState"
    ]
)

targets += composition(
    "OpenSkySessionAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyActors",
        "OpenSkyActorsInterface", "OpenSkyAgentControl", "OpenSkyAudio", "OpenSkyCells",
        "OpenSkyCombat", "OpenSkyCombatInterface", "OpenSkyConditions", "OpenSkyCrime",
        "OpenSkyCrimeInterface", "OpenSkyDialogue", "OpenSkyDialogueInterface",
        "OpenSkyEffects", "OpenSkyFactions", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsESS", "OpenSkyGameData", "OpenSkyInventory",
        "OpenSkyInventoryInterface", "OpenSkyLoading", "OpenSkyMagic", "OpenSkyMagicInterface",
        "OpenSkyMenus", "OpenSkyMenusInterface", "OpenSkyPerception", "OpenSkyPhysics",
        "OpenSkyPlayer", "OpenSkyProgression", "OpenSkyQuestsInterface", "OpenSkyRenderCore",
        "OpenSkyRenderResources", "OpenSkyRendering", "OpenSkyRuntimeState", "OpenSkySave",
        "OpenSkySaveInterface", "OpenSkyScripting", "OpenSkyScriptingInterface",
        "OpenSkySessionInterface", "OpenSkyWeather", "OpenSkyWorld", "OpenSkyWorldConditions",
        "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyWorldConditionFunctions"
    ]
)

targets += composition(
    "OpenSkyStoryAdapters",
    dependencies: [
        "OpenSkyAIPackages", "OpenSkyActorPresentation", "OpenSkyActorsInterface", "OpenSkyCells",
        "OpenSkyCombatInterface", "OpenSkyConditions", "OpenSkyCrime", "OpenSkyCrimeInterface",
        "OpenSkyDialogue", "OpenSkyDialogueInterface", "OpenSkyFactionsInterface",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyMenusInterface", "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyPlayer",
        "OpenSkyProgressionInterface", "OpenSkyQuests", "OpenSkyQuestsInterface",
        "OpenSkyRenderCore", "OpenSkyRendering", "OpenSkyRuntimeState", "OpenSkyScriptingInterface",
        "OpenSkySessionInterface", "OpenSkyWorld", "OpenSkyWorldConditions",
        "OpenSkyWorldInterface", "OpenSkyWorldState"
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
