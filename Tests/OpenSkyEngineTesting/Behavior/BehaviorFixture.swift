// Synthetic behavior graphs for the evaluator tests: dictionaries of decoded
// structs, not packfiles, because decode tests cover the bytes. All invented.
// `splineClip()` builds a real `HKASplineCompressedAnimation` from the
// synthetic packfile fixture, so clip time runs through the engine's sampler.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import simd

/// An in-memory `BehaviorObjectSource`: objects placed at offsets the test
/// chooses, so an assertion can name the node it is talking about.
nonisolated public struct BehaviorObjectTable: BehaviorObjectSource {
    private var objects: [HKXPointerTarget: any HKBClass] = [:]

    public init() {}

    /// Registers `object` at `offset` and returns the target that addresses it.
    @discardableResult
    public mutating func add(_ object: any HKBClass, at offset: Int) -> HKXPointerTarget {
        let target = BehaviorFixture.target(offset)
        objects[target] = object
        return target
    }

    public func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        objects[target]
    }

    public func className(at target: HKXPointerTarget) -> String? {
        objects[target]?.className
    }
}

/// A clip whose pose is a pure function of time, so a test can assert an exact
/// bone value at an exact local time without decoding anything.
nonisolated public struct BehaviorRampClip: BehaviorClip {
    public let duration: Float
    /// Bone index the ramp is written to.
    public let boneIndex: Int
    /// Translation at time t is `(t * rate, 0, 0)`.
    public let rate: Float

    public init(duration: Float = 1, boneIndex: Int = 0, rate: Float = 1) {
        self.duration = duration
        self.boneIndex = boneIndex
        self.rate = rate
    }

    public func samples(at time: Float) -> [HKABoneTransformSample] {
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
nonisolated public struct BehaviorStaticClip: BehaviorClip {
    public let duration: Float
    public let samples: [HKABoneTransformSample]

    public init(duration: Float = 1, samples: [HKABoneTransformSample]) {
        self.duration = duration
        self.samples = samples
    }

    public func samples(at _: Float) -> [HKABoneTransformSample] {
        samples
    }
}

/// One declared graph variable, for `BehaviorFixture.graphData`.
public struct BehaviorVariableSpec: Sendable {
    public let name: String
    public let type: HKBVariableType
    public let initial: Float

    public init(_ name: String, _ type: HKBVariableType, _ initial: Float) {
        self.name = name
        self.type = type
        self.initial = initial
    }
}

/// One clip trigger, for `BehaviorFixture.clipTriggers`.
public struct BehaviorTriggerSpec: Sendable {
    public let localTime: Float
    public let eventId: Int
    public var relativeToEnd = false
    public var acyclic = false

    public init(
        localTime: Float,
        eventId: Int,
        relativeToEnd: Bool = false,
        acyclic: Bool = false
    ) {
        self.localTime = localTime
        self.eventId = eventId
        self.relativeToEnd = relativeToEnd
        self.acyclic = acyclic
    }
}

/// One binding of a member path to a graph variable index.
public struct BehaviorBindingSpec: Sendable {
    public let memberPath: String
    public let variableIndex: Int

    public init(_ memberPath: String, _ variableIndex: Int) {
        self.memberPath = memberPath
        self.variableIndex = variableIndex
    }
}

/// Builders for the decoded structs a synthetic graph is made of.
public enum BehaviorFixture {
    /// Every fixture object lives in the data section, as in a real packfile.
    public static let section = 2

    public static func target(_ offset: Int) -> HKXPointerTarget {
        HKXPointerTarget(sectionIndex: section, dataOffset: offset)
    }

    // MARK: - Skeleton

    /// A three-bone rig: root, pelvis, hand. The root is bone 0, as on every
    /// vanilla Skyrim skeleton.
    public static func skeleton() -> BehaviorSkeleton {
        BehaviorSkeleton(
            referencePose: [
                bonePose(translation: SIMD3(0, 0, 0)),
                bonePose(translation: SIMD3(0, 10, 0)),
                bonePose(translation: SIMD3(0, 20, 0))
            ]
        )
    }

    public static func bonePose(
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
    public static func graphData(
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

    public static func nodeHeader(
        _ name: String,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBNodeHeader {
        HKBNodeHeader(variableBindingSet: bindingSet, userData: 0, name: name)
    }

    public static func modifierHeader(
        _ name: String,
        enable: Bool = true,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBModifierHeader {
        HKBModifierHeader(node: nodeHeader(name, bindingSet: bindingSet), enable: enable)
    }

    /// One binding of `memberPath` to variable `variableIndex`.
    public static func bindingSet(
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

    public static func clipGenerator(
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

    public static func blenderChild(
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

    public static func blender(
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

    public static func selector(
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

    public static func modifierGenerator(
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

    public static func clipTriggers(_ triggers: [BehaviorTriggerSpec]) -> HKBClipTriggerArray {
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
    public static func instance(
        root: HKXPointerTarget?,
        table: BehaviorObjectTable,
        data: HKBBehaviorGraphData = BehaviorFixture.graphData(),
        clips: any BehaviorClipSource = EmptyBehaviorClipSource()
    ) -> BehaviorGraphInstance {
        BehaviorGraphInstance(
            root: root,
            data: data,
            source: table,
            skeleton: skeleton(),
            clips: clips
        )
    }

    /// One bone sample at translation `(x, 0, 0)`.
    public static func sample(bone: Int, x: Float) -> HKABoneTransformSample {
        HKABoneTransformSample(
            boneIndex: bone,
            pose: bonePose(translation: SIMD3(x, 0, 0))
        )
    }

    /// Two static clips named `left` and `right`, holding bone 1 at the given
    /// translations.
    public static func staticClipPair(left: Float, right: Float) -> BehaviorClipTable {
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
    public static func splineClip(
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

public enum BehaviorFixtureError: Error {
    case noSplineAnimation
}
