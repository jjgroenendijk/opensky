// ACHR actors build and evict with their cell on the build queue. Worldspace-
// persistent ACHRs live under the worldspace persistent CELL and map into cells
// by position. Per cell: discovered = rendered + intentional skips + failures.
// Resolution documented in docs/engine/actor-resolution.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTerrain
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// Per-build actor accounting; folded into CellLoadSummary. The exact
/// invariant `discovered == rendered + disabledSkips + failures` is the 5.5
/// acceptance rule — every discovered ACHR must land in exactly one bucket.
nonisolated public struct ActorBuildCounts: Sendable {
    /// Non-deleted ACHRs owned by this cell: local persistent + temporary
    /// children plus position-mapped worldspace-persistent placements.
    var discovered = 0
    var rendered = 0
    /// Actors present but deliberately not drawn: initially-disabled ACHRs
    /// (record flag 0x800) and ones runtime state disabled or deleted. One
    /// bucket keeps the accounting rule above; the log line says which applied.
    var disabledSkips = 0
    /// Malformed ACHR records, unresolved template/visual chains, and
    /// assemblies with no core geometry.
    var failures = 0
    /// One human-readable reason per failure ("ACHR <id>: <why>") — the 5.6
    /// acceptance rule: every counted failure is explained, so
    /// `failureReasons.count == failures` always.
    public var failureReasons: [String] = []
    /// Rendered actors split exactly into animated + bind-pose fallback.
    var animated = 0
    var animationFailures = 0
    public var animationFailureReasons: [String] = []
    /// Every `AppearanceSkip`, per actor, as "ACHR <id>: <reason> (<subject>)".
    /// Not an error: a masked skin torso still reports one. The inventory readout
    /// uses it to say why an equipped piece drew nothing.
    var appearanceSkipReasons: [String] = []
}

/// Assembled actor render data handed to makeScene beside static instances.
nonisolated public struct CellActorBuild {
    public var placements: [RenderPlacement] = []
    public var animations: [any RenderAnimation] = []
    public var counts = ActorBuildCounts()
    var durationMS = 0.0
    /// Runtime index entries for every ACHR this cell owns, including ones not
    /// drawn: an initially-disabled actor still exists at runtime.
    var entries: [RuntimeReferenceEntry] = []
    /// Actors that exist but are disabled: the AI, the HUD, and the agent skip them.
    var disabledKeys: Set<ReferenceKey> = []
}

/// What an actor's `XESP` link may name besides the cell's own actors.
nonisolated public struct ActorEnableParents {
    public var references: [FormID: RuntimeReferenceEntry]
    public var pool: EnableParentPool

    public init(
        references: [FormID: RuntimeReferenceEntry] = [:],
        pool: EnableParentPool = EnableParentPool()
    ) {
        self.references = references
        self.pool = pool
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    /// Actors for one exterior cell: local ACHRs plus worldspace-persistent
    /// ACHRs whose physical position lies in this cell, resolved + assembled.
    nonisolated func buildExteriorActors(
        cell: FoundCell?,
        world: FoundWorld,
        coordinate: CellCoordinate,
        localized: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta] = [:],
        collision: StaticCollisionSet = .empty,
        parents: ActorEnableParents = ActorEnableParents()
    ) -> CellActorBuild {
        let started = Stopwatch()
        var malformed: [String] = []
        var byID: [UInt32: CollectedActor] = [:]
        for collected in decodeActors(in: cell, malformed: &malformed) {
            byID[collected.actor.formID.rawValue] = collected
        }
        // Records stored in the worldspace persistent CELL are persistent by
        // definition, whichever children group inside it holds them.
        for actor in persistentActors(in: world, localized: localized) {
            let actorCell = CellGridManager.cellCoordinate(for: actor.placement.position)
            guard actorCell == coordinate else { continue }
            byID[actor.formID.rawValue] = CollectedActor(actor: actor, isPersistent: true)
        }
        let collected = CellSceneBuilder.CellActorSpawnBuilder.standingOnFloors(
            owner.referenceBuilder.states.relocating(
                byID.values.sorted { $0.actor.formID.rawValue < $1.actor.formID.rawValue },
                into: .exterior(coordinate),
                deltas: deltas
            ) + spawns.spawnedActors(in: .exterior(coordinate), deltas: deltas),
            collision: collision
        )
        spawns.recordLeveledPlacements(
            collected, location: .exterior(coordinate),
            zone: cell?.cell.encounterZone ?? world.worldspace?.encounterZone
        )
        return resolvedBuild(
            (collected, malformed), parents: parents, deltas: deltas, started: started
        )
    }

    /// Actors for one interior cell — local children groups only; interiors
    /// have no worldspace persistent cell to map in.
    nonisolated func buildInteriorActors(
        cell: FoundCell?,
        location: CellSceneLocation,
        localized _: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta] = [:],
        collision: StaticCollisionSet = .empty,
        parents: ActorEnableParents = ActorEnableParents()
    ) -> CellActorBuild {
        let started = Stopwatch()
        var malformed: [String] = []
        let collected = CellSceneBuilder.CellActorSpawnBuilder.standingOnFloors(
            owner.referenceBuilder.states.relocating(
                decodeActors(in: cell, malformed: &malformed), into: location, deltas: deltas
            ) + spawns.spawnedActors(in: location, deltas: deltas),
            collision: collision
        )
        spawns.recordLeveledPlacements(
            collected,
            location: location,
            zone: cell?.cell.encounterZone
        )
        return resolvedBuild(
            (collected, malformed), parents: parents, deltas: deltas, started: started
        )
    }

    /// Counts, indexes, and resolves the collected actors of one cell build.
    nonisolated func resolvedBuild(
        _ scan: (collected: [CollectedActor], malformed: [String]),
        parents: ActorEnableParents,
        deltas: [ReferenceKey: ReferenceStateDelta],
        started: Stopwatch
    ) -> CellActorBuild {
        let (collected, malformed) = scan
        var build = CellActorBuild()
        let actors = collected.map(\.actor)
        build.entries = owner.referenceBuilder.actorEntries(collected, deltas: deltas)
        build.counts.discovered = actors.count + malformed.count
        build.counts.failures = malformed.count
        build.counts.failureReasons = malformed
        let enable = owner.enableResolver(
            entries: parents.references
                .merging(owner.referenceBuilder.states.entriesByFormID(build.entries)) { $1 },
            pool: parents.pool, deltas: deltas
        )
        resolver.resolveActors(actors, into: &build, deltas: deltas, enable: enable)
        build.durationMS =
            started.milliseconds
        return build
    }

    /// Non-deleted ACHRs of every plugin from the cell's persistent + temporary
    /// children groups. Deleted records place nothing (not discovered);
    /// a decode failure is discovered-but-failed.
    nonisolated private func decodeActors(
        in cell: FoundCell?,
        malformed: inout [String]
    ) -> [CollectedActor] {
        guard let cell else { return [] }
        let base = decodeBaseActors(in: cell.children, malformed: &malformed)
        return owner.recordIndex.mergingLaterActors(
            base,
            cell: FormID(cell.formID),
            malformed: &malformed
        )
    }

    nonisolated private func decodeBaseActors(
        in cellChildren: ESMGroup?,
        malformed: inout [String]
    ) -> [CollectedActor] {
        guard let cellChildren, let children = owner.records.childrenOrSkip(cellChildren) else {
            return []
        }
        var actors: [CollectedActor] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = owner.records.childrenOrSkip(group)
            else { continue }
            let isPersistent = group.kind == .cellPersistentChildren
            for case let .record(record) in records where record.type == "ACHR" {
                guard !record.isDeleted else { continue }
                do {
                    try actors.append(CollectedActor(
                        actor: PlacedActor(record: record), isPersistent: isPersistent
                    ))
                } catch {
                    let id = FormID(record.formID).description
                    malformed.append("ACHR \(id): malformed record")
                    CellSceneBuilder.logger
                        .warning("malformed ACHR \(id, privacy: .public) counted failed")
                }
            }
        }
        return actors
    }

    /// ACHRs of the worldspace persistent CELL, cached per WRLD like
    /// exteriorPersistentRefs. Malformed persistent records are logged once
    /// here — they carry no position, so no streamed cell can own (or count) them.
    nonisolated func persistentActors(
        in world: FoundWorld,
        localized: Bool
    ) -> [PlacedActor] {
        let key = world.formID.rawValue
        if let cached = owner.caches.exteriorPersistentActors[key] {
            return cached
        }
        var actors: [PlacedActor] = []
        if let persistent = owner.recordIndex.persistentCell(in: world, localized: localized) {
            var malformed: [String] = []
            actors = decodeActors(in: persistent, malformed: &malformed)
                .map(\.actor)
        }
        owner.caches.exteriorPersistentActors[key] = actors
        return actors
    }
}

/// One actor of a cell build, between its look resolution and its assembly.
nonisolated enum ActorBuildStep {
    case skipped(String, ReferenceKey?)
    /// `head` is the cut head of a decapitated actor, drawn as its own piece.
    case resolved(PlacedActor, ResolvedActorVisual, head: ResolvedActorVisual?)
    case failed(String)

    /// The model files the assembly reads: body parts with their thin siblings,
    /// attachments, head parts, and the face.
    var modelPaths: [String] {
        guard case let .resolved(_, visual, head) = self else { return [] }
        return ([visual] + [head].compactMap(\.self)).flatMap { visual in
            let parts = visual.parts.map(\.modelPath)
            return parts + parts.compactMap(BodyWeightBlend.thinPath(forHeavy:))
                + visual.attachments.map(\.modelPath) + visual.headParts.parts.map(\.modelPath)
                + [visual.faceGenMeshPath].compactMap(\.self)
        }
    }
}

nonisolated extension CellSceneBuilder {
    var actorBuilder: CellSceneBuilder.CellActorBuilder {
        CellSceneBuilder.CellActorBuilder(owner: self)
    }
}
