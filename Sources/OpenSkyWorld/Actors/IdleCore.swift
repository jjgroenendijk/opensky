// The rules of the idle runtime that need no session: which actors use idle
// markers, which marker an actor takes, and how long one idle plays.
// See docs/engine/idle-runtime.md.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One resident REFR whose base is an IDLM.
nonisolated public struct IdleMarkerPlacement: Sendable {
    public let reference: ReferenceKey
    public let marker: ResolvedRecord<IdleMarker>
    public let position: SIMD3<Float>

    public init(
        reference: ReferenceKey,
        marker: ResolvedRecord<IdleMarker>,
        position: SIMD3<Float>
    ) {
        self.reference = reference
        self.marker = marker
        self.position = position
    }
}

/// One resident REFR as the world reports it, before its base is resolved.
nonisolated public struct IdleReferencePlacement: Sendable {
    public let reference: ReferenceKey
    public let base: FormID
    /// The plugin that placed the reference; its base FormID is relative to it.
    public let plugin: String
    public let position: SIMD3<Float>

    public init(
        reference: ReferenceKey,
        base: FormID,
        plugin: String,
        position: SIMD3<Float>
    ) {
        self.reference = reference
        self.base = base
        self.plugin = plugin
        self.position = position
    }
}

/// One resident actor as the idle runtime sees it.
nonisolated public struct IdleActorPresence: Sendable {
    public let key: ReferenceKey
    public let feet: SIMD3<Float>
    /// The procedure of the actor's current package, nil without one.
    public let procedure: PackageProcedureKind?
    public let isDead: Bool

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        procedure: PackageProcedureKind?,
        isDead: Bool
    ) {
        self.key = key
        self.feet = feet
        self.procedure = procedure
        self.isDead = isDead
    }
}

nonisolated public enum IdleCore {
    /// How far an actor looks for a free marker, in world units (about 15 m).
    public static let claimRadius: Float = 1024
    /// Close enough to the marker to start idling.
    public static let arrivalRadius: Float = 48
    /// The clip event that kills the actor playing it, as the executionee's chop clip
    /// raises it. OpenSky's reading of the name; no source documents it.
    public static let killEvent = "KillActor"

    /// Sandbox and the use-idle-marker procedure send an actor to markers.
    public static func usesMarkers(_ procedure: PackageProcedureKind?) -> Bool {
        switch procedure {
        case .sandbox: true
        case let .unsupported(name): name.lowercased().contains("idlemarker")
        default: false
        }
    }

    /// The nearest marker within `claimRadius` that nobody holds and that is
    /// not in `excluded`. Ties go to the lower reference key.
    public static func nearestFreeMarker(
        to feet: SIMD3<Float>,
        among markers: [IdleMarkerPlacement],
        claimed: Set<ReferenceKey>,
        excluded: Set<ReferenceKey> = []
    ) -> IdleMarkerPlacement? {
        markers
            .filter { !claimed.contains($0.reference) && !excluded.contains($0.reference) }
            .map { (marker: $0, distance: simd_distance($0.position, feet)) }
            .filter { $0.distance <= claimRadius }
            .min { ($0.distance, $0.marker.reference) < ($1.distance, $1.marker.reference) }?
            .marker
    }

    /// The clip length times a loop count drawn from DATA's minimum and
    /// maximum. No DATA, or a zero maximum, plays the clip once.
    public static func playSeconds(
        clipDuration: Float,
        properties: IdleAnimation.Properties?,
        random: (Int) -> Int
    ) -> Float {
        guard let properties, properties.loopMaximum > 0 else { return clipDuration }
        let low = Int(min(properties.loopMinimum, properties.loopMaximum))
        let high = Int(properties.loopMaximum)
        let loops = max(1, low + min(max(random(high - low + 1), 0), high - low))
        return clipDuration * Float(loops)
    }

    /// The marker timer is the shortest stay; a longer clip still finishes. A held
    /// idle waits for the timer alone.
    public static func nextSelection(
        after start: Float,
        playSeconds: Float,
        timer: Float?
    ) -> Float {
        start + max(playSeconds.isFinite ? playSeconds : 0, timer ?? 0, 1)
    }

    /// A state whose clip loops holds until another idle replaces it, as a cart seat
    /// does. A loop count in the idle's `DATA` still ends it (docs/engine/idle-runtime.md).
    public static func holds(
        _ plan: IdlePlaybackPlan, properties: IdleAnimation.Properties?
    ) -> Bool {
        plan.loops && (properties?.loopMaximum ?? 0) == 0
    }

    /// The project folder above the skeleton's assets folder, such as
    /// `meshes\actors\character\` for `character assets female\skeleton_female.nif`.
    public static func graphProject(skeletonMeshPath: String) -> String? {
        let path = IdlePlaybackResolver.normalized(skeletonMeshPath)
        let parts = path.split(separator: "\\")
        guard let assets = parts.firstIndex(where: CreatureClipNames.isAssetsFolder) else {
            return nil
        }
        let folder = parts[..<assets].joined(separator: "\\") + "\\"
        return folder.hasPrefix("meshes\\") ? folder : "meshes\\" + folder
    }

    /// An idle plays only on the graph whose project folder holds its behavior file
    /// (`DNAM`). An idle with no file only groups others, so every graph may use it.
    public static func idle(behaviorFile: String?, belongsTo project: String) -> Bool {
        guard let behaviorFile, !behaviorFile.isEmpty else { return true }
        return IdlePlaybackResolver.projectFolder(of: behaviorFile) == project
    }

    public static func selectionOrder(of marker: IdleMarker) -> IdleSelectionOrder {
        (marker.flags ?? 0) & 0x01 != 0 ? .sequence : .random
    }

    public static func isDoOnce(_ marker: IdleMarker) -> Bool {
        (marker.flags ?? 0) & 0x04 != 0
    }

    /// The clip's annotations over `seconds` of looping, as seconds from the start.
    /// A script hears them as animation events, such as `ExitCartEnd`.
    public static func annotationEvents(
        _ annotations: [HKAAnnotation], clipDuration: Float, seconds: Float
    ) -> [IdleAnimationEvent] {
        markEvents(
            clipMarks(annotations: annotations, triggers: [], clipDuration: clipDuration),
            clipDuration: clipDuration, seconds: seconds
        )
    }

    /// The clip's marks over `seconds` of looping, as seconds from the start.
    public static func markEvents(
        _ marks: [IdleAnimationEvent], clipDuration: Float, seconds: Float
    ) -> [IdleAnimationEvent] {
        guard clipDuration > 0, !marks.isEmpty else { return [] }
        var events: [IdleAnimationEvent] = []
        var loopStart: Float = 0
        while loopStart < seconds {
            for mark in marks where loopStart + mark.time <= seconds {
                events.append(IdleAnimationEvent(time: loopStart + mark.time, name: mark.name))
            }
            loopStart += clipDuration
        }
        return events
    }

    /// The clip's annotations and its generator's triggers, in time order inside one loop.
    public static func clipMarks(
        annotations: [HKAAnnotation], triggers: [BehaviorClipTriggerEvent], clipDuration: Float
    ) -> [IdleAnimationEvent] {
        let marks = annotations.map { IdleAnimationEvent(time: $0.time, name: $0.text) }
            + triggers.map {
                IdleAnimationEvent(time: $0.seconds(inClipOf: clipDuration), name: $0.name)
            }
        return marks.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }
}

nonisolated extension IdleCore {
    /// The state's enter events at the start, the annotations, then its exit events at
    /// the end, in time order. The game leaves the state when the idle ends.
    public static func playEvents(
        marks: [IdleAnimationEvent], notify: BehaviorStateNotify,
        clipDuration: Float, seconds: Float
    ) -> [IdleAnimationEvent] {
        notify.enter.map { IdleAnimationEvent(time: 0, name: $0) }
            + markEvents(marks, clipDuration: clipDuration, seconds: seconds)
            + notify.exit.map { IdleAnimationEvent(time: seconds, name: $0) }
    }
}

/// One clip annotation an idle sends, at seconds from the idle's start.
nonisolated public struct IdleAnimationEvent: Equatable, Sendable {
    public let time: Float
    public let name: String

    public init(time: Float, name: String) {
        self.time = time
        self.name = name
    }
}
