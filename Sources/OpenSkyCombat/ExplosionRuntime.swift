// Detonates explosions: damage with falloff, both sounds, the image-space
// modifier at the viewer's strength, a placed hazard, and thrown debris. One
// entry point serves projectiles, area spells, and the sidebar.
// See docs/formats/explosions.md, section "Runtime".

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

@MainActor
public final class ExplosionRuntime {
    public static let reportLimit = 8

    public weak var world: (any ExplosionWorld)?
    /// The load-order effect records. Empty until the session wires them.
    public var records = EffectRecordStore.empty
    /// The plugin raw item links (a PROJ's explosion) are written in.
    public var itemPlugin = "Skyrim.esm"
    public private(set) var reports: [ExplosionReport] = []
    public private(set) var debris: [DebrisPiece] = []
    public private(set) var detonationTotal = 0
    /// Placed objects that were neither a hazard nor debris.
    public private(set) var skippedPlacements = 0
    private var seed: UInt64 = 0x0E5D_1A57

    public init() {}

    /// The explosion a raw link in the item plugin names.
    public func spec(itemLink id: FormID?) -> ExplosionSpec? {
        records.resolve(id, fromPlugin: itemPlugin).flatMap(spec(for:))
    }

    public func spec(for key: ReferenceKey) -> ExplosionSpec? {
        guard let resolved = records.explosions.record(key) else { return nil }
        return Self.spec(resolved, key: key, records: records)
    }

    /// Detonates `spec` at `position` and returns what it did.
    @discardableResult
    public func detonate(
        _ spec: ExplosionSpec,
        at position: SIMD3<Float>,
        cause: ExplosionCause
    ) -> ExplosionReport {
        detonationTotal += 1
        var damaged: [ReferenceKey: Float] = [:]
        if spec.damage > 0, let world {
            for target in world.explosionTargets() {
                let amount = ExplosionFalloff.damage(
                    spec.damage, radius: spec.radius, distance: Self.distance(position, target)
                )
                if amount > 0, world.applyExplosionDamage(amount, to: target.key) {
                    damaged[target.key] = amount
                }
            }
        }
        for sound in spec.sounds {
            world?.playExplosionSound(sound, at: position)
        }
        if let model = spec.model {
            world?.showExplosionModel(model, at: position)
        }
        let strength = startImageSpace(spec, at: position)
        let (hazard, thrown) = place(spec, at: position)
        let report = ExplosionReport(
            name: spec.name, cause: cause, position: position, damaged: damaged,
            soundsPlayed: world == nil ? 0 : spec.sounds.count, imageSpaceStrength: strength,
            hazardPlaced: hazard, debrisThrown: thrown
        )
        reports.append(report)
        if reports.count > Self.reportLimit {
            reports.removeFirst(reports.count - Self.reportLimit)
        }
        return report
    }

    /// Throws `count` pieces of one DEBR record at `position`, for the sidebar.
    @discardableResult
    public func throwDebris(_ key: ReferenceKey, at position: SIMD3<Float>, force: Float) -> Int {
        guard let record = records.debris.record(key)?.record else { return 0 }
        seed &+= 1
        let pieces = DebrisSelection.launch(record.models, from: position, force: force, seed: seed)
        debris += pieces
        return pieces.count
    }

    /// Advances the debris and drops the pieces whose time ran out.
    public func advance(_ seconds: Float) {
        guard !debris.isEmpty else { return }
        debris = DebrisSelection.step(debris, seconds: seconds)
    }

    public func clear() {
        debris = []
        reports = []
    }

    private func startImageSpace(_ spec: ExplosionSpec, at position: SIMD3<Float>) -> Float? {
        guard let modifier = spec.imageSpaceModifier, let world else { return nil }
        let viewer = world.explosionViewer() ?? position
        let strength = ExplosionFalloff.imageSpaceStrength(
            radius: spec.imageSpaceRadius, distance: simd_distance(viewer, position)
        )
        guard strength > 0 else { return nil }
        world.startExplosionImageSpace(modifier, strength: strength)
        return strength
    }

    private func place(_ spec: ExplosionSpec, at position: SIMD3<Float>) -> (Bool, Int) {
        switch spec.placement {
        case let .hazard(key):
            return (world?.placeExplosionHazard(key, at: position) ?? false, 0)
        case let .debris(key):
            return (false, throwDebris(key, at: position, force: spec.force))
        case .other:
            skippedPlacements += 1
            return (false, 0)
        case nil:
            return (false, 0)
        }
    }

    /// From the blast center to the nearest point of the target's capsule axis.
    private static func distance(_ center: SIMD3<Float>, _ target: MeleeTarget) -> Float {
        let (first, second) = target.segment
        let axis = second - first
        let length = simd_length_squared(axis)
        let along = length > 0 ? min(max(simd_dot(center - first, axis) / length, 0), 1) : 0
        return simd_distance(center, first + axis * along)
    }

    static func spec(
        _ resolved: ResolvedRecord<Explosion>,
        key: ReferenceKey,
        records: EffectRecordStore
    ) -> ExplosionSpec {
        let explosion = resolved.record
        let data = explosion.properties
        let sounds = [data?.sound1, data?.sound2].compactMap {
            records.resolve($0, from: resolved)
        }
        let placement = records.resolve(data?.placedObject, from: resolved).map { placed in
            let type = records.recordType(placed).map { "\($0)" } ?? "?"
            return switch type {
            case "HAZD": ExplosionPlacement.hazard(placed)
            case "DEBR": ExplosionPlacement.debris(placed)
            default: ExplosionPlacement.other(placed, type: type)
            }
        }
        return ExplosionSpec(
            name: explosion.editorID ?? "\(key)",
            damage: Self.clean(data?.damage),
            radius: Self.clean(data?.radius),
            force: Self.clean(data?.force),
            imageSpaceRadius: Self.clean(data?.imageSpaceRadius),
            sounds: sounds,
            imageSpaceModifier: records.resolve(explosion.imageSpaceModifier, from: resolved),
            placement: placement,
            model: explosion.model?.path
        )
    }

    private static func clean(_ value: Float?) -> Float {
        guard let value, value.isFinite else { return 0 }
        return max(value, 0)
    }
}
