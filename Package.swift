// swift-tools-version: 6.2
// The engine, one module per layer, laid out by The Modular Architecture
// (docs/tools/modules.md). The app and OpenSkyCLI link one umbrella product,
// OpenSkyModules, and the Xcode test bundles link OpenSkyTestSupport, so a new
// module never edits the project file. OpenSky.xcworkspace holds the project and
// this package side by side.
//
// Modules are declared bottom-up. A module may depend only on modules declared
// before it, and a feature module never depends on another feature's
// implementation, only on its interface. The helpers below stop the manifest from
// loading when either rule breaks, and the compiler rejects an import a target
// does not list.

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

/// The app and openskycli link ffmpeg through OTHER_LDFLAGS. A package test
/// executable has no such setting, so the test targets link it here.
let testLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-L\(ffmpeg)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(ffmpeg)/lib"]),
    .linkedLibrary("avcodec"),
    .linkedLibrary("avutil"),
    .linkedLibrary("swresample")
]

// MARK: - Module helpers

/// Every declared module, in declaration order. The layering checks read it.
nonisolated(unsafe) var declared: [String] = []
/// Feature implementations. Nothing but the composition roots may depend on one.
nonisolated(unsafe) var featureImplementations: Set<String> = []
/// Targets the umbrella products export.
nonisolated(unsafe) var libraryTargets: [String] = []
nonisolated(unsafe) var testingTargets: [String] = []

/// Rejects a dependency on a module declared later (the same layer or above) and a
/// dependency on another feature's implementation.
func checked(_ module: String, _ dependencies: [String]) -> [Target.Dependency] {
    for dependency in dependencies {
        precondition(
            declared.contains(dependency),
            "\(module) depends on \(dependency), which is not declared below it"
        )
        precondition(
            !featureImplementations.contains(dependency),
            "\(module) depends on the feature implementation \(dependency); use its interface"
        )
    }
    return dependencies.map { .target(name: $0) }
}

func testTarget(_ name: String, dependencies: [String]) -> Target {
    .testTarget(
        name: name,
        dependencies: dependencies.map { .target(name: $0) },
        swiftSettings: testSettings,
        linkerSettings: testLinkerSettings
    )
}

/// A foundation module: a library with a stable public API that every module above
/// may import directly. No interface split. `tests` adds `<name>Tests`.
func foundation(
    _ name: String,
    dependencies: [String] = [],
    exclude: [String] = [],
    tests: [String]? = nil
) -> [Target] {
    let library = Target.target(
        name: name,
        dependencies: checked(name, dependencies),
        exclude: exclude,
        swiftSettings: librarySettings
    )
    declared.append(name)
    libraryTargets.append(name)
    guard let tests else { return [library] }
    return [library, testTarget("\(name)Tests", dependencies: [name] + tests)]
}

/// Fakes and fixtures other modules' tests share: `Tests/<name>/`.
func testing(_ name: String, dependencies: [String]) -> [Target] {
    let target = Target.target(
        name: name,
        dependencies: checked(name, dependencies),
        path: "Tests/\(name)",
        swiftSettings: testSettings
    )
    declared.append(name)
    testingTargets.append(name)
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

/// A feature module, by The Modular Architecture:
/// - `<name>`: the implementation. Only the composition roots import it.
/// - `<name>Interface`: the protocols and value types other modules use. Declared
///   when `interface` is non-nil; its dependencies are the list given. An interface
///   declared earlier with `interface(_:dependencies:)` is used instead.
/// - `<name>Testing`: fakes and fixtures other modules' tests share. Declared when
///   `testing` is non-nil.
/// - `<name>Tests`: the unit tests of `<name>`. Declared when `tests` is non-nil;
///   its extra dependencies are the list given.
func feature(
    _ name: String,
    dependencies: [String] = [],
    interface: [String]? = nil,
    testing testingDependencies: [String]? = nil,
    tests: [String]? = nil
) -> [Target] {
    var targets: [Target] = []
    let interfaceName = "\(name)Interface"
    if let interface {
        targets.append(.target(
            name: interfaceName,
            dependencies: checked(interfaceName, interface),
            swiftSettings: librarySettings
        ))
        declared.append(interfaceName)
        libraryTargets.append(interfaceName)
    }
    let ownInterface = interface != nil || declared.contains(interfaceName) ? [interfaceName] : []
    targets.append(.target(
        name: name,
        dependencies: checked(name, ownInterface + dependencies),
        swiftSettings: librarySettings
    ))
    declared.append(name)
    libraryTargets.append(name)
    featureImplementations.insert(name)
    if let testingDependencies {
        targets += testing("\(name)Testing", dependencies: ownInterface + testingDependencies)
    }
    if let tests {
        let testingTarget = testingDependencies == nil ? [] : ["\(name)Testing"]
        targets.append(testTarget("\(name)Tests", dependencies: [name] + testingTarget + tests))
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
    }
    let library = Target.target(
        name: name,
        dependencies: dependencies.map { .target(name: $0) },
        swiftSettings: librarySettings
    )
    declared.append(name)
    libraryTargets.append(name)
    featureImplementations.insert(name)
    guard let tests else { return [library] }
    return [library, testTarget("\(name)Tests", dependencies: [name] + tests)]
}

// MARK: - Modules, bottom-up

/// The structs shared with Metal. Shaders.metal includes the same header.
let shaderTypes = Target.target(
    name: "OpenSkyShaderTypes",
    publicHeadersPath: "."
)
/// The vendored ffmpeg as a clang module (Sources/CFFmpeg/module.modulemap).
let cffmpeg = Target.systemLibrary(name: "CFFmpeg")
declared += ["OpenSkyShaderTypes", "CFFmpeg"]

var targets: [Target] = [shaderTypes, cffmpeg]

// Foundation

// Formats: a core of binary readers, compression, geometry values, archives and
// string tables, then one module per format family. A family depends only on the
// core, so a parser change rebuilds one family and the modules that use it.
targets += foundation("OpenSkyFormatsCore", tests: ["FormatsCoreTesting"])
targets += testing("FormatsCoreTesting", dependencies: ["OpenSkyFormatsCore"])
/// The test target above names FormatsCoreTesting before the helper declares it;
/// SwiftPM resolves target names lazily, so only the layering check needs the order.
let formatFamilies = ["ESM", "Mesh", "Animation", "Audio", "PEX", "SWF"]
for family in formatFamilies {
    let module = "OpenSkyFormats\(family)"
    let fixtures = "Formats\(family)Testing"
    targets += foundation(
        module,
        dependencies: ["OpenSkyFormatsCore"],
        tests: [fixtures, "FormatsCoreTesting", "OpenSkyFormatsCore"]
    )
    targets += testing(
        fixtures,
        dependencies: [module, "OpenSkyFormatsCore", "FormatsCoreTesting"]
    )
}

targets += foundation(
    "OpenSkyGameData",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyFormatsPEX",
        "OpenSkyFormatsSWF"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "FormatsCoreTesting", "FormatsESMTesting", "FormatsPEXTesting"
    ]
)
targets += foundation(
    "OpenSkyBehavior",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "OpenSkyGameData"],
    tests: ["BehaviorTesting", "OpenSkyFormatsCore", "OpenSkyFormatsAnimation"]
)
targets += testing(
    "BehaviorTesting",
    dependencies: ["OpenSkyBehavior", "OpenSkyFormatsAnimation", "FormatsAnimationTesting"]
)

targets += foundation("OpenSkyDiagnostics", dependencies: ["OpenSkyShaderTypes"])
targets += foundation(
    "OpenSkyPhysics",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyGameData", "OpenSkyBehavior"
    ],
    tests: [
        "PhysicsTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "FormatsCoreTesting", "FormatsMeshTesting"
    ]
)
targets += testing(
    "PhysicsTesting",
    dependencies: [
        "OpenSkyPhysics", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyGameData"
    ]
)

targets += foundation(
    "OpenSkyAudio",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAudio", "OpenSkyGameData",
        "CFFmpeg"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsAudio", "OpenSkyGameData",
        "FormatsCoreTesting", "FormatsESMTesting", "FormatsAudioTesting"
    ]
)

targets += foundation(
    "OpenSkyRendering",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF",
        "OpenSkyGameData", "OpenSkyDiagnostics", "OpenSkyPhysics", "OpenSkyShaderTypes"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyPhysics", "OpenSkyShaderTypes",
        "FormatsCoreTesting", "FormatsESMTesting", "FormatsMeshTesting"
    ]
)

targets += foundation(
    "OpenSkyWorldState",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "FormatsCoreTesting", "FormatsESMTesting"
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
targets += testing(
    "OpenSkyWorldTesting",
    dependencies: [
        "OpenSkyWorldInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState"
    ]
)
targets += interface(
    "OpenSkyInventory",
    dependencies: [
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyWorldState"
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
        "OpenSkyActorsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState", "FormatsCoreTesting", "FormatsESMTesting"
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
    testing: [
        "OpenSkyFormatsESM",
        "OpenSkyGameData",
        "OpenSkyActorsInterface",
        "FormatsESMTesting"
    ],
    tests: [
        "OpenSkyFactionsInterface", "OpenSkyActorsInterface", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyConditions",
        "FormatsCoreTesting", "FormatsESMTesting"
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
        "OpenSkyProgressionInterface", "OpenSkyActors", "OpenSkyActorsInterface",
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyConditions",
        "FormatsCoreTesting", "FormatsESMTesting"
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
    testing: ["OpenSkyFormatsESM", "OpenSkyPhysics"],
    tests: [
        "OpenSkyPerceptionInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyPhysics",
        "OpenSkyDiagnostics", "OpenSkyShaderTypes"
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
    testing: ["OpenSkyFormatsESM", "OpenSkyGameData", "FormatsCoreTesting", "FormatsESMTesting"],
    tests: [
        "OpenSkyMagicInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState", "OpenSkyConditions", "OpenSkyPhysics", "OpenSkyActorsInterface",
        "OpenSkyActors", "OpenSkyProgressionInterface", "OpenSkyInventoryInterface",
        "OpenSkyInventory", "OpenSkyInventoryTesting", "OpenSkyPerceptionInterface",
        "FormatsCoreTesting", "FormatsESMTesting"
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
    testing: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyFactionsInterface", "FormatsCoreTesting", "FormatsESMTesting"
    ],
    tests: [
        "OpenSkyCrimeInterface", "OpenSkyActorsInterface", "OpenSkyFactionsInterface",
        "OpenSkyInventoryInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState", "OpenSkyConditions", "FormatsCoreTesting", "FormatsESMTesting"
    ]
)
targets += feature(
    "OpenSkyInventory",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyFactionsInterface", "OpenSkyCrimeInterface", "OpenSkyMagicInterface",
        "OpenSkyWorldInterface"
    ],
    testing: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "FormatsCoreTesting", "FormatsESMTesting"
    ],
    tests: [
        "OpenSkyInventoryInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState", "OpenSkyFactionsInterface", "OpenSkyCrimeInterface",
        "OpenSkyMagicInterface", "OpenSkyWorldInterface", "OpenSkyWorldTesting",
        "FormatsCoreTesting", "FormatsESMTesting"
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
        "OpenSkyCombatInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsAnimation", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics",
        "OpenSkyWorldState", "OpenSkyConditions", "OpenSkyActorsInterface", "OpenSkyActors",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyMagic",
        "OpenSkyMagicTesting", "OpenSkyPerceptionInterface", "OpenSkyProgressionInterface",
        "OpenSkyWorldInterface", "OpenSkyShaderTypes", "FormatsCoreTesting", "FormatsESMTesting",
        "BehaviorTesting", "PhysicsTesting"
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
        "OpenSkyQuestsInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyWorldState", "OpenSkyConditions", "FormatsCoreTesting", "FormatsESMTesting"
    ]
)
targets += feature(
    "OpenSkyDialogue",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyQuestsInterface"
    ],
    interface: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyConditions", "OpenSkyQuestsInterface"
    ],
    tests: [
        "OpenSkyDialogueInterface",
        "OpenSkyFormatsCore",
        "OpenSkyFormatsESM",
        "OpenSkyGameData"
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
        "OpenSkyWorldInterface"
    ],
    interface: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyWorldState"],
    tests: [
        "OpenSkyScriptingInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsPEX", "OpenSkyGameData", "OpenSkyWorldState", "OpenSkyQuestsInterface",
        "OpenSkyQuests", "FormatsESMTesting", "FormatsPEXTesting"
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
        "OpenSkyDialogueInterface", "OpenSkyScriptingInterface", "OpenSkyShaderTypes"
    ],
    tests: [
        "OpenSkyWorldInterface", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh",
        "OpenSkyFormatsAnimation", "OpenSkyGameData", "OpenSkyBehavior", "OpenSkyPhysics",
        "OpenSkyRendering", "OpenSkyAudio", "OpenSkyWorldState", "OpenSkyActorsInterface",
        "OpenSkyCombat", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkyShaderTypes",
        "FormatsCoreTesting", "FormatsESMTesting", "FormatsMeshTesting", "FormatsAnimationTesting",
        "BehaviorTesting", "PhysicsTesting"
    ]
)

targets += feature(
    "OpenSkySave",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyActorsInterface", "OpenSkyCrimeInterface", "OpenSkyDialogueInterface",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyQuestsInterface", "OpenSkyScriptingInterface"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState",
        "OpenSkyActorsInterface", "OpenSkyActors", "OpenSkyCrimeInterface",
        "OpenSkyFactionsInterface", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyProgressionInterface", "OpenSkyProgression", "OpenSkyQuestsInterface",
        "FormatsCoreTesting", "FormatsESMTesting"
    ]
)

targets += feature(
    "OpenSkyMenus",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsSWF", "OpenSkyGameData",
        "OpenSkyRendering", "OpenSkyActorsInterface", "OpenSkyDialogueInterface",
        "OpenSkyInventoryInterface", "OpenSkyQuestsInterface", "OpenSkyScriptingInterface",
        "OpenSkyWorldInterface"
    ],
    tests: [
        "OpenSkyFormatsESM", "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyRendering",
        "OpenSkyWorldState", "OpenSkyInventoryInterface", "OpenSkyInventory",
        "OpenSkyInventoryTesting", "OpenSkyQuestsInterface", "OpenSkyQuests", "OpenSkyShaderTypes",
        "FormatsESMTesting", "FormatsSWFTesting"
    ]
)

// Composition: code the app and OpenSkyCLI share.
targets += composition(
    "OpenSkyPreview",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyConditions", "OpenSkyRendering", "OpenSkyWorld"
    ],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "FormatsCoreTesting", "FormatsESMTesting"
    ]
)

let package = Package(
    name: "OpenSky",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenSkyModules", targets: ["OpenSkyShaderTypes"] + libraryTargets),
        .library(name: "OpenSkyTestSupport", targets: testingTargets)
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
