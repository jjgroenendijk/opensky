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

/// Every declared module, in declaration order. The layering checks read it.
nonisolated(unsafe) var declared: [String] = []
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
    return dependencies.map { .target(name: $0) }
}

func testTarget(_ name: String, dependencies: [String]) -> Target {
    .testTarget(
        name: name,
        dependencies: (["TagsTesting"] + dependencies).map { .target(name: $0) },
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

/// A feature module: `<name>` (the implementation), plus `<name>Interface`,
/// `<name>Testing`, and `<name>Tests` when the matching argument is non-nil.
/// An interface declared earlier with `interface(_:dependencies:)` is reused.
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
    guard let tests else { return [library] }
    return [library, testTarget("\(name)Tests", dependencies: [name] + tests)]
}

// MARK: - Modules, bottom-up

/// The structs shared with Metal. Shaders.metal includes the same header.
let shaderTypes = Target.target(
    name: "OpenSkyShaderTypes",
    publicHeadersPath: "."
)
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
        .linkedLibrary("avcodec"),
        .linkedLibrary("avutil"),
        .linkedLibrary("swresample")
    ]
)
declared += ["OpenSkyShaderTypes", "CFFmpeg"]

var targets: [Target] = [shaderTypes, cffmpeg]

// The Swift Testing tags every test target links through `testTarget`.
targets += testing("TagsTesting", dependencies: [])

// Foundation

// Formats: a core of binary readers, compression, geometry values, archives and
// string tables, then one module per format family. A family depends only on the
// core, so a parser change rebuilds one family and the modules that use it.
targets += foundation("OpenSkyFormatsCore", tests: [
    "FormatsCoreTesting"
])
targets += testing("FormatsCoreTesting", dependencies: [
    "OpenSkyFormatsCore"
])
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
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "FormatsCoreTesting", "FormatsESMTesting",
        "FormatsPEXTesting", "OpenSkyFormatsPEX",
        "GameDataTesting",
        "WorldStateTesting"
    ]
)
targets += testing(
    "GameDataTesting",
    dependencies: [
        "FormatsESMTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"
    ]
)
targets += foundation(
    "OpenSkyBehavior",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "OpenSkyGameData"],
    tests: [
        "BehaviorTesting", "OpenSkyFormatsCore", "OpenSkyFormatsAnimation", "FormatsMeshTesting",
        "OpenSkyFormatsMesh"
    ]
)
targets += testing(
    "BehaviorTesting",
    dependencies: [
        "FormatsAnimationTesting", "OpenSkyBehavior", "OpenSkyFormatsAnimation"
    ]
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
        "FormatsCoreTesting", "FormatsMeshTesting", "FormatsESMTesting", "OpenSkyGameData"
    ]
)
targets += testing(
    "PhysicsTesting",
    dependencies: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyGameData",
        "OpenSkyPhysics"
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
        "OpenSkyPhysics", "OpenSkyShaderTypes", "FormatsCoreTesting", "FormatsESMTesting",
        "FormatsMeshTesting", "OpenSkyFormatsSWF", "RenderingTesting"
    ]
)
targets += testing("RenderingTesting", dependencies: [
    "OpenSkyFormatsCore", "OpenSkyRendering"
])

targets += foundation(
    "OpenSkyWorldState",
    dependencies: ["OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData"],
    tests: [
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyRendering",
        "FormatsCoreTesting", "FormatsESMTesting",
        "WorldStateTesting"
    ]
)
targets += testing(
    "WorldStateTesting",
    dependencies: [
        "FormatsESMTesting", "OpenSkyFormatsESM", "OpenSkyWorldState"
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
    testing: [
        "OpenSkyGameData", "OpenSkyWorldState"
    ],
    tests: [
        "OpenSkyActorsInterface", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldState"
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
        "FormatsESMTesting", "OpenSkyActorsInterface", "OpenSkyFormatsESM", "OpenSkyGameData"
    ],
    tests: [
        "FormatsESMTesting", "OpenSkyActorsInterface", "OpenSkyFactionsFixtures",
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
        "OpenSkyActorsInterface", "OpenSkyActorsTesting", "OpenSkyConditions",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyMagicTesting", "OpenSkyProgressionFixtures",
        "OpenSkyProgressionInterface", "OpenSkyProgressionTesting", "OpenSkyWorldState"
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
    testing: [
        "OpenSkyFormatsESM", "OpenSkyPhysics"
    ],
    tests: [
        "OpenSkyDiagnostics", "OpenSkyFormatsESM", "OpenSkyPerceptionInterface", "OpenSkyPhysics",
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
        "OpenSkyActorsInterface", "OpenSkyActorsTesting", "OpenSkyConditions",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagicFixtures",
        "OpenSkyMagicInterface", "OpenSkyMagicTesting", "OpenSkyProgressionInterface",
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
    testing: [
        "FormatsCoreTesting", "FormatsESMTesting", "OpenSkyFactionsInterface", "OpenSkyFormatsESM",
        "OpenSkyGameData"
    ],
    tests: [
        "FormatsESMTesting", "OpenSkyActorsInterface", "OpenSkyCrimeFixtures",
        "OpenSkyCrimeInterface", "OpenSkyFactionsInterface", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyWorldInterface",
        "OpenSkyWorldState"
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
        "FormatsCoreTesting", "FormatsESMTesting", "OpenSkyFormatsESM", "OpenSkyGameData"
    ],
    tests: [
        "FormatsESMTesting", "OpenSkyCrimeInterface", "OpenSkyFactionsInterface",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyWorldInterface", "OpenSkyWorldState",
        "OpenSkyWorldTesting"
    ]
)
targets += testing(
    "OpenSkyMagicTesting",
    dependencies: [
        "FormatsCoreTesting", "FormatsESMTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyWorldState"
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
        "OpenSkyActorsInterface", "OpenSkyBehavior", "OpenSkyCombatFixtures",
        "OpenSkyCombatInterface", "OpenSkyFormatsAnimation", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyInventoryInterface", "OpenSkyMagicInterface", "OpenSkyPerceptionInterface",
        "OpenSkyPhysics", "OpenSkyProgressionInterface", "OpenSkyWorldState", "PhysicsTesting"
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
    testing: [
        "OpenSkyFormatsESM", "OpenSkyGameData"
    ],
    tests: [
        "FormatsESMTesting", "GameDataTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyGameData", "OpenSkyQuestsInterface", "OpenSkyWorldState", "WorldStateTesting"
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
        "OpenSkyConditions", "OpenSkyDialogueFixtures", "OpenSkyDialogueInterface",
        "OpenSkyDialogueTesting", "OpenSkyFormatsESM", "OpenSkyGameData",
        "OpenSkyQuestsInterface", "OpenSkyWorldState", "OpenSkyWorldTesting"
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
        "FormatsESMTesting", "FormatsPEXTesting", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsPEX", "OpenSkyGameData", "OpenSkyQuestsTesting", "OpenSkyScriptingFixtures",
        "OpenSkyScriptingInterface", "OpenSkyWorldState"
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
        "BehaviorTesting", "FormatsAnimationTesting", "FormatsAudioTesting", "FormatsCoreTesting",
        "FormatsESMTesting", "FormatsMeshTesting", "FormatsSWFTesting", "GameDataTesting",
        "OpenSkyActorsInterface", "OpenSkyAudio", "OpenSkyBehavior", "OpenSkyConditions",
        "OpenSkyCrimeInterface", "OpenSkyCrimeTesting", "OpenSkyDiagnostics",
        "OpenSkyDialogueInterface", "OpenSkyFactionsInterface", "OpenSkyFormatsAnimation",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF",
        "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagicInterface",
        "OpenSkyPerceptionInterface", "OpenSkyPhysics", "OpenSkyProgressionInterface",
        "OpenSkyQuestsInterface", "OpenSkyRendering", "OpenSkyShaderTypes", "OpenSkyWorldFixtures",
        "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyWorldTesting", "PhysicsTesting",
        "RenderingTesting", "WorldStateTesting"
    ]
)

// Testing libraries that use the world testing library, declared above it.
targets += testing(
    "OpenSkyWorldTesting",
    dependencies: [
        "FormatsCoreTesting", "FormatsESMTesting", "OpenSkyAudio", "OpenSkyConditions",
        "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyWorldInterface",
        "OpenSkyWorldState", "WorldStateTesting"
    ]
)
targets += testing(
    "OpenSkyProgressionTesting",
    dependencies: [
        "FormatsCoreTesting", "FormatsESMTesting", "GameDataTesting", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyMagicTesting", "OpenSkyWorldState"
    ]
)
targets += testing(
    "OpenSkyDialogueTesting",
    dependencies: [
        "FormatsESMTesting", "GameDataTesting", "OpenSkyConditions", "OpenSkyDialogueInterface",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyQuestsInterface", "OpenSkyWorldState",
        "OpenSkyWorldTesting"
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
        "FormatsCoreTesting", "FormatsESMTesting", "OpenSkyActorsInterface",
        "OpenSkyCrimeInterface", "OpenSkyFactionsInterface", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface",
        "OpenSkyMagicInterface", "OpenSkyQuestsInterface", "OpenSkySaveFixtures",
        "OpenSkyWorldState", "WorldStateTesting"
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
        "FormatsCoreTesting", "FormatsESMTesting", "FormatsSWFTesting", "OpenSkyFormatsCore",
        "OpenSkyFormatsESM", "OpenSkyFormatsSWF", "OpenSkyGameData", "OpenSkyRendering",
        "OpenSkyShaderTypes", "OpenSkyWorldInterface", "RenderingTesting"
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
        "OpenSkyCrime", "OpenSkyCrimeInterface", "OpenSkyCrimeTesting", "OpenSkyFormatsESM",
        "OpenSkyInventoryInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyDialogue",
    dependencies: [
        "OpenSkyConditions", "OpenSkyDialogue", "OpenSkyDialogueInterface",
        "OpenSkyDialogueTesting", "OpenSkyQuestsInterface", "OpenSkyWorldState"
    ]
)
targets += fixtures(
    "OpenSkyFactions",
    dependencies: [
        "OpenSkyFactions", "OpenSkyFactionsTesting", "OpenSkyGameData"
    ]
)
targets += fixtures(
    "OpenSkyMagic",
    dependencies: [
        "OpenSkyFormatsESM", "OpenSkyGameData", "OpenSkyInventoryInterface", "OpenSkyMagic",
        "OpenSkyMagicInterface", "OpenSkyMagicTesting", "OpenSkyProgressionInterface",
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
        "FormatsCoreTesting", "FormatsESMTesting", "FormatsPEXTesting", "OpenSkyFormatsESM",
        "OpenSkyFormatsPEX", "OpenSkyGameData", "OpenSkyScripting", "OpenSkyScriptingInterface",
        "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyWorldTesting"
    ]
)
targets += fixtures(
    "OpenSkyWorld",
    dependencies: [
        "FormatsAudioTesting", "FormatsCoreTesting", "FormatsESMTesting", "FormatsMeshTesting",
        "OpenSkyAudio", "OpenSkyConditions", "OpenSkyFormatsCore", "OpenSkyFormatsESM",
        "OpenSkyFormatsMesh", "OpenSkyGameData", "OpenSkyPhysics", "OpenSkyRendering",
        "OpenSkyWorld", "OpenSkyWorldInterface", "OpenSkyWorldState", "OpenSkyWorldTesting",
        "RenderingTesting"
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
        "FormatsCoreTesting", "FormatsESMTesting",
        "GameDataTesting"
    ]
)

let package = Package(
    name: "OpenSky",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenSkyModules", targets: ["OpenSkyShaderTypes"] + libraryTargets),
        .library(name: "OpenSkyTestSupport", targets: testingTargets + fixtureTargets)
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
