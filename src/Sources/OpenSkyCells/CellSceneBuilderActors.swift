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

nonisolated struct CellActorBuilder {
    let owner: CellSceneBuilder
}

nonisolated extension CellActorBuilder {
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
        let collected = Self.standingOnFloors(owner.referenceBuilder.relocating(
            byID.values.sorted { $0.actor.formID.rawValue < $1.actor.formID.rawValue },
            into: .exterior(coordinate),
            deltas: deltas
        ) + spawnedActors(in: .exterior(coordinate), deltas: deltas), collision: collision)
        recordLeveledPlacements(
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
        let collected = Self.standingOnFloors(owner.referenceBuilder.relocating(
            decodeActors(in: cell, malformed: &malformed), into: location, deltas: deltas
        ) + spawnedActors(in: location, deltas: deltas), collision: collision)
        recordLeveledPlacements(collected, location: location, zone: cell?.cell.encounterZone)
        return resolvedBuild(
            (collected, malformed), parents: parents, deltas: deltas, started: started
        )
    }

    /// Records the cell's zone for its containers, and each actor's zone (its own
    /// `XEZN`, else the cell's) and `XLCM` by reference and by base, before its
    /// template chain rolls.
    nonisolated func recordLeveledPlacements(
        _ collected: [CollectedActor], location: CellSceneLocation, zone: FormID?
    ) {
        let zones = owner.encounterZones ?? EncounterZoneStore(plugins: owner.loadOrderPlugins)
        owner.encounterZones = zones
        let cellZone = zone.flatMap { zones.resolve($0, fromPlugin: owner.pluginName)?.zone }
        owner.leveling.placements.record(cell: location, zone: cellZone)
        for collectedActor in collected {
            let actor = collectedActor.actor
            let own = actor.details.links["XEZN"].flatMap {
                zones.resolve($0, fromPlugin: FormIDResolver.loadOrderSpaceName)?.zone
            }
            let placement = LeveledActorPlacement(
                zone: own ?? cellZone,
                difficulty: LeveledActorDifficulty(levelModifier: actor.details.levelModifier)
            )
            owner.leveling.placements.record(actor: actor.base, placement)
            let key = collectedActor.spawnKey
                ?? ReferenceKey.resolve(actor.formID, using: owner.formIDResolver)
            if let key {
                owner.leveling.placements.record(reference: key, placement)
            }
        }
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
                .merging(owner.referenceBuilder.entriesByFormID(build.entries)) { $1 },
            pool: parents.pool, deltas: deltas
        )
        resolveActors(actors, into: &build, deltas: deltas, enable: enable)
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
        guard let cellChildren, let children = owner.childrenOrSkip(cellChildren) else {
            return []
        }
        var actors: [CollectedActor] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = owner.childrenOrSkip(group)
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
        if let cached = owner.exteriorPersistentActors[key] {
            return cached
        }
        var actors: [PlacedActor] = []
        if let persistent = owner.recordIndex.persistentCell(in: world, localized: localized) {
            var malformed: [String] = []
            actors = decodeActors(in: persistent, malformed: &malformed)
                .map(\.actor)
        }
        owner.exteriorPersistentActors[key] = actors
        return actors
    }

    /// Resolves each ACHR through the template + visual chains, assembles GPU
    /// assets via MeshLibrary, and buckets every actor exactly once. Per-actor
    /// failures log + count and never abort the build (mod-quirk rule).
    nonisolated private func resolveActors(
        _ actors: [PlacedActor],
        into build: inout CellActorBuild,
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) {
        guard !actors.isEmpty else { return }
        let indexed = owner.referenceBuilder.entriesByFormID(build.entries)
        let steps = actors.map { actor in
            resolveStep(actor, entry: indexed[actor.formID], deltas: deltas, enable: enable)
        }
        // Every look is known before the first assembly, so the part files load on every core.
        owner.meshes.preparse(paths: steps.flatMap(\.modelPaths))
        defer { owner.meshes.dropPreparsed() }
        let assembler = ActorAssembler(provider: owner.meshes)
        for (actor, step) in zip(actors, steps) {
            let id = actor.formID.description
            switch step {
            case let .skipped(skip, key):
                build.counts.disabledSkips += 1
                if let key {
                    build.disabledKeys.insert(key)
                }
                CellSceneBuilder.logger
                    .info("ACHR \(id, privacy: .public): \(skip, privacy: .public), skipped")
            case let .resolved(placed, visual, head):
                record(assembler.assemble(placed: placed, visual: visual), id: id, into: &build)
                if let head {
                    recordSeveredHead(
                        assembler.assemble(placed: placed, visual: head), into: &build
                    )
                }
            case let .failed(reason):
                build.counts.failures += 1
                build.counts.failureReasons.append("ACHR \(id): unresolved (\(reason))")
                CellSceneBuilder.logger.warning(
                    """
                    ACHR \(id, privacy: .public): unresolved \
                    (\(reason, privacy: .public)), failed
                    """
                )
            }
        }
    }

    /// The runtime skip, or the resolved look, of one actor. Reads records only.
    nonisolated private func resolveStep(
        _ actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) -> ActorBuildStep {
        if let skip = actorRuntimeSkip(actor: actor, entry: entry, deltas: deltas, enable: enable) {
            return .skipped(skip, entry?.key)
        }
        let resolvers = actorResolversBuildingIfNeeded()
        do {
            let roll = entry.map {
                owner.referenceBuilder.leveledRoll(of: $0.key, base: actor.base, deltas: deltas)
            }
            let templates = resolvers.template.rolling(roll)
            let appearance = try templates.resolve(base: actor.base)
            var visual = try resolvers.visual.resolve(
                appearance: appearance,
                equipped: runtimeEquipment(entry: entry, deltas: deltas),
                roll: roll,
                carried: templates.carriedItems(base: actor.base)
            ).presenting(
                entry.flatMap { deltas[$0.key]?.component(ActorPresentationState.self) },
                textureSets: resolvers.visual.textureSets
            )
            if
                visual.headSource == .assembled,
                let face = PlayerAppearanceOverride(face: appearance)
            {
                visual = chargenVisual(visual, appearance: face)
            }
            let placed = actorApplyingRuntimeTransform(actor, entry: entry, deltas: deltas)
            let death = entry.flatMap { deltas[$0.key]?.component(ActorDeathState.self) }
            guard death?.severedNode != nil else { return .resolved(placed, visual, head: nil) }
            let cut = visual.decapitated(gore: resolvers.visual.decapitationGore(for: visual))
            return .resolved(placed, cut.body, head: cut.head)
        } catch {
            return .failed(String(describing: error))
        }
    }

    nonisolated private func actorApplyingRuntimeTransform(
        _ actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> PlacedActor {
        guard
            let entry,
            let transform = deltas[entry.key]?.component(ReferenceTransformOverride.self)
        else { return actor }
        return PlacedActor(
            copying: actor,
            placement: transform.placement,
            scale: transform.scale
        )
    }

    /// Buckets one assembled actor: drawn plus its animation outcome, or a
    /// counted failure with its reason. Split out of `resolveActors` so both
    /// stay inside the strict-lint function-body cap.
    nonisolated private func record(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        id: String,
        into build: inout CellActorBuild
    ) {
        build.counts.appearanceSkipReasons += Self.appearanceSkipLines(assembly, id: id)
        guard assembly.isRenderable else {
            build.counts.failures += 1
            let reasons = assembly.skips.map { String(describing: $0.reason) }
                .joined(separator: ", ")
            build.counts.failureReasons.append(
                "ACHR \(id): no renderable geometry (\(reasons))"
            )
            CellSceneBuilder.logger.warning(
                """
                ACHR \(id, privacy: .public): no renderable geometry \
                (\(reasons, privacy: .public)), failed
                """
            )
            return
        }
        build.counts.rendered += 1
        let faceMorph = makeFaceMorphPlayback(assembly: assembly)
        build.placements.append(contentsOf: assembly.renderPlacements(
            at: assembly.transform,
            faceMorphs: faceMorph?.renderBuffers ?? [:],
            owner: assembly.actor.rawValue,
            reference: assembly.actor.rawValue
        ))
        var skeleton: ActorAnimationPlayback?
        switch makeAnimationPlayback(assembly: assembly) {
        case let .success(playback):
            build.counts.animated += 1
            skeleton = playback
        case let .failure(error):
            build.counts.animationFailures += 1
            build.counts.animationFailureReasons.append(
                "ACHR \(id): \(error.localizedDescription)"
            )
        }
        if let faceMorph {
            build.animations.append(faceMorph)
            build.animations.append(LipSyncPlayback(faceMorph: faceMorph, head: skeleton))
        }
        if let skeleton {
            build.animations.append(skeleton)
        }
    }

    /// A cut head: drawn at its actor, posed by its own playback so it can fall apart from
    /// the body. Its outcome is not counted, because the actor is already counted.
    nonisolated private func recordSeveredHead(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        into build: inout CellActorBuild
    ) {
        guard
            assembly.isRenderable,
            case let .success(playback) = makeAnimationPlayback(
                assembly: assembly, severedHead: true
            )
        else { return }
        build.placements.append(contentsOf: assembly.renderPlacements(
            at: assembly.transform,
            owner: assembly.actor.rawValue,
            reference: assembly.actor.rawValue,
            isCulled: false
        ))
        build.animations.append(playback)
    }

    /// The assembly's `AppearanceSkip` entries as readable lines, one per skip.
    ///
    /// Only the `.appearance` subject is taken: the other `ActorAssemblySkip`
    /// subjects are asset-loading outcomes, which the failure buckets above
    /// already own, and mixing the two would make a missing NIF read as a
    /// resolution decision.
    nonisolated private static func appearanceSkipLines(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        id: String
    ) -> [String] {
        assembly.skips.compactMap { skip in
            guard case let .appearance(appearance) = skip.subject else { return nil }
            return "ACHR \(id): \(appearance.reason) (\(appearance.subject))"
        }
    }

    /// The equipped set a changed actor renders from, or nil while its default
    /// outfit still applies. The baseline is the outfit, so the first equip
    /// keeps the outfit and adds the new piece.
    nonisolated private func runtimeEquipment(
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [FormID]? {
        guard let entry, let delta = deltas[entry.key] else { return nil }
        return delta.component(ReferenceInventoryState.self)?.equipped
    }

    /// Why this actor is not drawn, or nil when it should be. An `XESP` parent
    /// decides alone, as for references; an actor with no index entry only has
    /// its record flag.
    nonisolated private func actorRuntimeSkip(
        actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) -> String? {
        guard let entry else {
            return actor.isInitiallyDisabled ? "initially disabled" : nil
        }
        let resolved = owner.referenceBuilder.resolvedRuntimeState(for: entry, deltas: deltas)
        if resolved.deletion.isDeleted {
            return "deleted at runtime"
        }
        guard !enable.isEnabled(entry) else { return nil }
        return resolved.overriddenKinds.contains(.enableState)
            ? "disabled at runtime"
            : "initially disabled"
    }

    /// Template + visual resolver pair over the plugin's NPC_/LVLN and
    /// RACE/ARMO/ARMA/OTFT/LVLI top groups, built once and reused across
    /// every cell build (shared like statIndex). Internal rather than private
    /// because the player body resolves through the same pair
    /// (CellSceneBuilderPlayer.swift) and must not force a second copy of two
    /// plugin-wide indexes into memory.
    nonisolated func actorResolversBuildingIfNeeded()
        -> (template: ActorTemplateResolver, visual: ActorVisualResolver)
    {
        if let template = owner.actorTemplateResolver, let visual = owner.actorVisualResolver {
            return (template, visual)
        }
        let loadOrder = owner.interiorBuilder.loadOrderIndexBuildingIfNeeded().loadOrder
        let (template, visual) = owner.loadPhases.measure(.actorIndex) {
            (
                ActorTemplateResolver.build(from: loadOrder, leveling: owner.leveling),
                ActorVisualResolver.build(from: loadOrder, leveling: owner.leveling)
            )
        }
        owner.actorTemplateResolver = template
        owner.actorVisualResolver = visual
        return (template, visual)
    }
}

/// One actor of a cell build, between its look resolution and its assembly.
nonisolated private enum ActorBuildStep {
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
    var actorBuilder: CellActorBuilder {
        CellActorBuilder(owner: self)
    }
}
