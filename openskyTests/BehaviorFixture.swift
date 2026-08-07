// Synthetic behavior graphs for the evaluator tests (issue #187).
//
// The evaluator reads decoded objects through `BehaviorObjectSource`, so a test
// graph is a dictionary of decoded structs rather than a packfile: the byte
// layouts are already covered by the decode tests, and repeating them here
// would test the fixture instead of the evaluator. Everything below is
// invented — no extracted game data anywhere (AGENTS.md "Legal & IP boundary").
//
// The one exception is the clip: `splineClip()` builds a real
// `HKASplineCompressedAnimation` from the shared synthetic packfile fixture, so
// clip time advance and looping are exercised through the same sampling seam
// the engine uses.

import Foundation
@testable import opensky
import simd

/// An in-memory `BehaviorObjectSource`: objects placed at offsets the test
/// chooses, so an assertion can name the node it is talking about.
nonisolated struct BehaviorObjectTable: BehaviorObjectSource {
    private var objects: [HKXPointerTarget: any HKBClass] = [:]

    init() {}

    /// Registers `object` at `offset` and returns the target that addresses it.
    @discardableResult
    mutating func add(_ object: any HKBClass, at offset: Int) -> HKXPointerTarget {
        let target = BehaviorFixture.target(offset)
        objects[target] = object
        return target
    }

    func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        objects[target]
    }

    func className(at target: HKXPointerTarget) -> String? {
        objects[target]?.className
    }
}

/// A clip whose pose is a pure function of time, so a test can assert an exact
/// bone value at an exact local time without decoding anything.
nonisolated struct BehaviorRampClip: BehaviorClip {
    let duration: Float
    /// Bone index the ramp is written to.
    let boneIndex: Int
    /// Translation at time t is `(t * rate, 0, 0)`.
    let rate: Float

    init(duration: Float = 1, boneIndex: Int = 0, rate: Float = 1) {
        self.duration = duration
        self.boneIndex = boneIndex
        self.rate = rate
    }

    func samples(at time: Float) -> [HKABoneTransformSample] {
        let clamped = min(max(time, 0), duration)
        return [HKABoneTransformSample(
            boneIndex: boneIndex,
            pose: HKABonePose(
                translation: SIMD3(clamped * rate, 0, 0),
                rotation: BehaviorPoseMath.identityRotation,
                scale: SIMD3(1, 1, 1)
            )
        )]
    }
}

/// A clip that holds one fixed pose, for blend arithmetic that must not move
/// while it is being asserted on.
nonisolated struct BehaviorStaticClip: BehaviorClip {
    let duration: Float
    let samples: [HKABoneTransformSample]

    init(duration: Float = 1, samples: [HKABoneTransformSample]) {
        self.duration = duration
        self.samples = samples
    }

    func samples(at _: Float) -> [HKABoneTransformSample] {
        samples
    }
}

/// One declared graph variable, for `BehaviorFixture.graphData`.
struct BehaviorVariableSpec {
    let name: String
    let type: HKBVariableType
    let initial: Float

    init(_ name: String, _ type: HKBVariableType, _ initial: Float) {
        self.name = name
        self.type = type
        self.initial = initial
    }
}

/// One clip trigger, for `BehaviorFixture.clipTriggers`.
struct BehaviorTriggerSpec {
    let localTime: Float
    let eventId: Int
    var relativeToEnd = false
    var acyclic = false
}

/// One binding of a member path to a graph variable index.
struct BehaviorBindingSpec {
    let memberPath: String
    let variableIndex: Int

    init(_ memberPath: String, _ variableIndex: Int) {
        self.memberPath = memberPath
        self.variableIndex = variableIndex
    }
}

/// Builders for the decoded structs a synthetic graph is made of.
enum BehaviorFixture {
    /// Every fixture object lives in the data section, as in a real packfile.
    static let section = 2

    static func target(_ offset: Int) -> HKXPointerTarget {
        HKXPointerTarget(sectionIndex: section, dataOffset: offset)
    }

    // MARK: - Skeleton

    /// A three-bone rig: root, pelvis, hand. The root is bone 0, as on every
    /// vanilla Skyrim skeleton.
    static func skeleton() -> BehaviorSkeleton {
        BehaviorSkeleton(
            boneNames: ["NPC Root [Root]", "NPC Pelvis [Pelv]", "NPC Hand [Hand]"],
            referencePose: [
                bonePose(translation: SIMD3(0, 0, 0)),
                bonePose(translation: SIMD3(0, 10, 0)),
                bonePose(translation: SIMD3(0, 20, 0))
            ]
        )
    }

    static func bonePose(
        translation: SIMD3<Float>,
        rotation: simd_quatf = BehaviorPoseMath.identityRotation,
        scale: SIMD3<Float> = SIMD3(1, 1, 1)
    ) -> HKABonePose {
        HKABonePose(translation: translation, rotation: rotation, scale: scale)
    }

    // MARK: - Graph declarations

    /// Builds `hkbBehaviorGraphData` from variable and event declarations. The
    /// initial value of a real variable is given as a float and stored as the
    /// bit pattern the packfile would hold.
    static func graphData(
        variables: [BehaviorVariableSpec] = [],
        events: [String] = []
    ) -> HKBBehaviorGraphData {
        HKBBehaviorGraphData(
            attributeDefaults: [],
            variableInfos: variables.map {
                HKBVariableInfo(rawType: $0.type.rawValue, type: $0.type)
            },
            characterPropertyInfos: [],
            eventFlags: [UInt32](repeating: 0, count: events.count),
            wordMinVariableValues: [],
            wordMaxVariableValues: [],
            variableInitialValues: HKBVariableValueSet(
                wordValues: variables.map { word(for: $0.type, value: $0.initial) },
                quadValues: variables.map { SIMD4($0.initial, 0, 0, 0) },
                variantCount: 0,
                unresolved: []
            ),
            stringData: HKBBehaviorGraphStringData(
                eventNames: events,
                attributeNames: [],
                variableNames: variables.map(\.name),
                characterPropertyNames: [],
                unresolved: []
            ),
            unresolved: []
        )
    }

    private static func word(for type: HKBVariableType, value: Float) -> Int {
        switch type {
        case .real: Int(Int32(bitPattern: value.bitPattern))
        default: Int(value)
        }
    }

    // MARK: - Nodes

    static func nodeHeader(
        _ name: String,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBNodeHeader {
        HKBNodeHeader(variableBindingSet: bindingSet, userData: 0, name: name)
    }

    static func modifierHeader(
        _ name: String,
        enable: Bool = true,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBModifierHeader {
        HKBModifierHeader(node: nodeHeader(name, bindingSet: bindingSet), enable: enable)
    }

    /// One binding of `memberPath` to variable `variableIndex`.
    static func bindingSet(
        _ bindings: [BehaviorBindingSpec],
        indexOfBindingToEnable: Int = -1
    ) -> HKBVariableBindingSet {
        HKBVariableBindingSet(
            bindings: bindings.map {
                HKBVariableBinding(
                    memberPath: $0.memberPath,
                    variableIndex: $0.variableIndex,
                    bitIndex: -1,
                    bindingType: 0
                )
            },
            indexOfBindingToEnable: indexOfBindingToEnable,
            unresolved: []
        )
    }

    static func clipGenerator(
        _ name: String,
        animationName: String,
        mode: Int = 1,
        playbackSpeed: Float = 1,
        startTime: Float = 0,
        triggers: HKXPointerTarget? = nil,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBClipGenerator {
        HKBClipGenerator(
            node: nodeHeader(name, bindingSet: bindingSet),
            animationName: animationName,
            triggers: triggers,
            cropStartAmountLocalTime: 0,
            cropEndAmountLocalTime: 0,
            startTime: startTime,
            playbackSpeed: playbackSpeed,
            enforcedDuration: 0,
            userControlledTimeFraction: 0,
            animationBindingIndex: -1,
            mode: mode,
            flags: 0,
            unresolved: []
        )
    }

    static func blenderChild(
        generator: HKXPointerTarget?,
        weight: Float,
        worldFromModelWeight: Float = 1,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBBlenderGeneratorChild {
        HKBBlenderGeneratorChild(
            variableBindingSet: bindingSet,
            generator: generator,
            boneWeights: nil,
            weight: weight,
            worldFromModelWeight: worldFromModelWeight,
            unresolved: []
        )
    }

    static func blender(
        _ name: String,
        children: [HKXPointerTarget?],
        threshold: Float = 0,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBBlenderGenerator {
        HKBBlenderGenerator(
            node: nodeHeader(name, bindingSet: bindingSet),
            blender: HKBBlenderFields(
                referencePoseWeightThreshold: threshold,
                blendParameter: 0,
                minCyclicBlendParameter: 0,
                maxCyclicBlendParameter: 0,
                indexOfSyncMasterChild: -1,
                flags: 0,
                subtractLastChild: false,
                children: children
            ),
            unresolved: []
        )
    }

    static func selector(
        _ name: String,
        generators: [HKXPointerTarget?],
        selected: Int = 0,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBManualSelectorGenerator {
        HKBManualSelectorGenerator(
            node: nodeHeader(name, bindingSet: bindingSet),
            generators: generators,
            selectedGeneratorIndex: selected,
            currentGeneratorIndex: selected,
            unresolved: []
        )
    }

    static func modifierGenerator(
        _ name: String,
        modifier: HKXPointerTarget?,
        generator: HKXPointerTarget?
    ) -> HKBModifierGenerator {
        HKBModifierGenerator(
            node: nodeHeader(name),
            modifier: modifier,
            generator: generator,
            unresolved: []
        )
    }

    static func clipTriggers(_ triggers: [BehaviorTriggerSpec]) -> HKBClipTriggerArray {
        HKBClipTriggerArray(
            triggers: triggers.map {
                HKBClipTrigger(
                    localTime: $0.localTime,
                    event: HKBEventProperty(id: $0.eventId, payload: nil),
                    relativeToEndOfClip: $0.relativeToEnd,
                    acyclic: $0.acyclic,
                    isAnnotation: false
                )
            },
            unresolved: []
        )
    }

    // MARK: - Instances

    /// A graph instance over the three-bone rig, ready to step.
    static func instance(
        root: HKXPointerTarget?,
        table: BehaviorObjectTable,
        data: HKBBehaviorGraphData = BehaviorFixture.graphData(),
        clips: any BehaviorClipSource = EmptyBehaviorClipSource()
    ) -> BehaviorGraphInstance {
        BehaviorGraphInstance(
            name: "test",
            root: root,
            data: data,
            source: table,
            skeleton: skeleton(),
            clips: clips
        )
    }

    /// One bone sample at translation `(x, 0, 0)`.
    static func sample(bone: Int, x: Float) -> HKABoneTransformSample {
        HKABoneTransformSample(
            boneIndex: bone,
            pose: bonePose(translation: SIMD3(x, 0, 0))
        )
    }

    /// Two static clips named `left` and `right`, holding bone 1 at the given
    /// translations.
    static func staticClipPair(left: Float, right: Float) -> BehaviorClipTable {
        BehaviorClipTable(byName: [
            "left": BehaviorStaticClip(samples: [sample(bone: 1, x: left)]),
            "right": BehaviorStaticClip(samples: [sample(bone: 1, x: right)])
        ])
    }

    // MARK: - Clips

    /// The shared synthetic spline clip: one second long, one transform track
    /// whose translation.x ramps 0 to 30, bound onto `boneIndex`. Bone 1 by
    /// default, because bone 0 is the root and its travel is extracted rather
    /// than posed.
    static func splineClip(
        boneIndex: Int = 1,
        carriesExtractedMotion: Bool = false,
        annotations: [(time: Float, text: String)] = []
    ) throws -> SplineBehaviorClip {
        var fixture = HKASplineAnimationFixture()
        fixture.carriesExtractedMotion = carriesExtractedMotion
        if !annotations.isEmpty {
            fixture.annotationTracks = [(name: "NPC Root [Root]", annotations: annotations)]
        }
        let file = try HKXFile(data: fixture.build())
        let animations = try HKASplineCompressedAnimation.animations(in: file)
        guard let animation = animations.first else {
            throw BehaviorFixtureError.noSplineAnimation
        }
        return SplineBehaviorClip(
            animation: animation,
            binding: HKAAnimationBinding(
                originalSkeletonName: "TestRig",
                animationTarget: nil,
                transformTrackToBoneIndices: [boneIndex],
                floatTrackToSlotIndices: [],
                blendHint: 0
            )
        )
    }
}

enum BehaviorFixtureError: Error {
    case noSplineAnimation
}
