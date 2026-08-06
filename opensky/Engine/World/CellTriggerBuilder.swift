// Per-cell trigger-volume assembly (issue #173), split from
// CellCollisionBuilder.swift for file-length limits and to keep the static
// collision loop — a hot path whose `filteredBodyCount` accounting is pinned by
// the CLI grid acceptance — untouched.
//
// Two authored sources feed one `TriggerVolumeSet`:
//
// 1. SkyrimLayer 12 bodies inside a placed NIF. `buildStaticCollision` keeps
//    only player-solid bodies, so these are dropped there; a second pass over
//    the same cached models routes them here instead.
// 2. `XPRM` primitives on the REFR itself (docs/formats/records.md), which
//    authors trigger boxes and spheres with no mesh behind them at all.
//
// Both run on the build queue inside the same `SerialCellBuildRunner` call as
// the render scene, and the resulting set is immutable once built.

import Foundation
import simd

/// Both immutable collision products of one cell build. They are produced
/// together because they share the same reference list and the same NIF cache,
/// and travel together onto the `CellScene`.
nonisolated struct CellCollisionBuild {
    let staticCollision: StaticCollisionSet
    let triggerVolumes: TriggerVolumeSet
    /// Bodies of this cell the dynamic world simulates (issue #193). Empty for
    /// a build with no reference retention, because a simulated body needs the
    /// `ReferenceKey` the entries carry.
    var dynamicBodies: [DynamicBodyPlacement] = []
}

nonisolated extension CellSceneBuilder {
    /// The solid set and the trigger set for one cell, from the references a
    /// build settled on after runtime state was applied.
    nonisolated func buildCollision(
        resolved: EffectiveReferences,
        location: CellSceneLocation
    ) -> CellCollisionBuild {
        let products = buildCollisionProducts(
            refs: resolved.references,
            location: location,
            keys: resolved.entries.reduce(into: [:]) { keys, entry in
                keys[entry.formID] = entry.key
            }
        )
        return CellCollisionBuild(
            staticCollision: products.collision,
            triggerVolumes: buildTriggerVolumes(
                refs: resolved.references, entries: resolved.entries, location: location
            ),
            dynamicBodies: products.dynamicBodies
        )
    }

    /// Every authored trigger volume of one cell.
    ///
    /// - Parameters:
    ///   - refs: the cell's effective references, runtime deltas already
    ///     applied, so a moved or rescaled reference triggers where it now is.
    ///   - entries: the runtime index entries for those references, which carry
    ///     the `ReferenceKey` a script instance is addressed by. A reference
    ///     with no entry has no runtime identity, so its volume would name
    ///     nothing and is skipped and counted instead.
    ///   - location: the cell the set belongs to.
    ///
    /// Volume order is deterministic: primitives in reference order first, then
    /// mesh bodies in reference, body and shape order.
    nonisolated func buildTriggerVolumes(
        refs: [PlacedReference],
        entries: [RuntimeReferenceEntry],
        location: CellSceneLocation
    ) -> TriggerVolumeSet {
        guard !refs.isEmpty else {
            return TriggerVolumeSet(location: location, volumes: [])
        }
        var keys: [FormID: ReferenceKey] = [:]
        keys.reserveCapacity(entries.count)
        for entry in entries {
            keys[entry.formID] = entry.key
        }
        var stats = TriggerVolumeStats()
        var volumes = primitiveTriggerVolumes(refs: refs, keys: keys, stats: &stats)
        volumes += meshTriggerVolumes(refs: refs, keys: keys, stats: &stats)
        return TriggerVolumeSet(location: location, volumes: volumes, stats: stats)
    }

    // MARK: - XPRM primitives

    /// Trigger volumes authored directly on the REFR as an `XPRM` primitive.
    ///
    /// The primitive's half-extents are pre-scale and in the reference's local
    /// frame, so the placement matrix — position, DATA rotation and `XSCL`,
    /// built by the same `MatrixMath.placement` call
    /// `resolveCollisionPlacements` uses so there is one Euler convention —
    /// carries both the pose and the scale.
    nonisolated private func primitiveTriggerVolumes(
        refs: [PlacedReference],
        keys: [FormID: ReferenceKey],
        stats: inout TriggerVolumeStats
    ) -> [TriggerVolume] {
        var volumes: [TriggerVolume] = []
        for ref in refs {
            guard let primitive = ref.primitive else { continue }
            guard let geometry = Self.triggerGeometry(of: primitive) else {
                stats.excludedPrimitiveCount += 1
                continue
            }
            guard let key = keys[ref.formID] else {
                stats.unkeyedReferenceCount += 1
                continue
            }
            let placed = TriggerVolume.placed(
                reference: key,
                formID: ref.formID,
                transform: MatrixMath.placement(
                    position: ref.placement.position,
                    rotation: ref.placement.rotation,
                    scale: ref.scale
                ),
                geometry: geometry
            )
            guard let placed else {
                stats.degenerateVolumeCount += 1
                continue
            }
            volumes.append(placed)
            stats.primitiveVolumeCount += 1
        }
        return volumes
    }

    /// The collision geometry an `XPRM` primitive stands for, or nil when the
    /// primitive is deliberately not a gameplay trigger.
    ///
    /// Only `box` and `sphere` become volumes. `portalBox` is occlusion
    /// room-portal geometry and `line` is not a volume at all, so treating
    /// either as a trigger would fire `OnTriggerEnter` for scripts that never
    /// asked; `none` describes no shape. All three are counted as exclusions
    /// rather than silently dropped (docs/engine/collision-world.md).
    ///
    /// A sphere's radius is `halfExtents.x`: neither UESP's REFR page nor
    /// xEdit's `wbStruct(XPRM, ...)` names an axis, but every one of the 137
    /// sphere primitives in `Skyrim.esm` stores the same value in all three
    /// axes (`PlacedReferenceXPRMRealDataTests`, observed 2026-07-31), so the
    /// three are interchangeable and no axis is being guessed.
    nonisolated static func triggerGeometry(
        of primitive: PlacedReference.Primitive
    ) -> NIFCollisionGeometry? {
        switch primitive.type {
        case .box:
            .box(halfExtents: primitive.halfExtents)
        case .sphere:
            .sphere(radius: primitive.halfExtents.x)
        case .none, .portalBox, .line:
            nil
        }
    }

    // MARK: - Layer 12 NIF bodies

    /// Trigger volumes from the SkyrimLayer 12 bodies of the cell's placed
    /// NIFs. Models come from the same build-queue-confined
    /// `NIFCollisionLibrary` cache the static build already populated, so this
    /// pass decodes nothing a second time.
    nonisolated private func meshTriggerVolumes(
        refs: [PlacedReference],
        keys: [FormID: ReferenceKey],
        stats: inout TriggerVolumeStats
    ) -> [TriggerVolume] {
        guard let collisionModels else { return [] }
        var volumes: [TriggerVolume] = []
        for placement in resolveCollisionPlacements(refs: refs) {
            guard let model = try? collisionModels.model(path: placement.modelPath) else {
                continue
            }
            guard model.bodies.contains(where: \.isTriggerVolume) else { continue }
            guard let key = keys[placement.reference] else {
                stats.unkeyedReferenceCount += 1
                continue
            }
            for body in model.bodies where body.isTriggerVolume {
                for shape in body.shapes {
                    let placed = TriggerVolume.placed(
                        reference: key,
                        formID: placement.reference,
                        transform: placement.transform * body.transform * shape.transform,
                        geometry: shape.geometry
                    )
                    guard let placed else {
                        stats.degenerateVolumeCount += 1
                        continue
                    }
                    volumes.append(placed)
                    stats.meshVolumeCount += 1
                }
            }
        }
        return volumes
    }
}
