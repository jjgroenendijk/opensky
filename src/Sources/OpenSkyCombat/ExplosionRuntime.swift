// Detonates explosions: damage with falloff, both sounds, the image-space
// modifier at the viewer's strength, a placed hazard, and thrown debris. One
// entry point serves projectiles, area spells, and agent control.
// See docs/formats/explosions.md, section "Runtime".

import Foundation
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import simd

@MainActor
public final class ExplosionRuntime {
    public static let reportLimit = 8
    /// `EXPL` `DATA` flag Ignore Image Space Swap.
    static let ignoreSwapFlag: UInt32 = 0x40
    /// `EXPL` `DATA` flag Ignore LOS.
    static let ignoreLineOfSightFlag: UInt32 = 0x10

    public weak let world: (any ExplosionWorld)?
    /// The load-order effect records. Empty without game data.
    public let records: EffectRecordStore
    /// The plugin raw item links (a PROJ's explosion) are written in.
    public let itemPlugin: String
    public private(set) var reports: [ExplosionReport] = []
    public private(set) var debris: [DebrisPiece] = []
    public private(set) var detonationTotal = 0
    var seed: UInt64 = 0x0E5D_1A57
    /// The push settings and the readout log. Nil pushes nothing.
    public var impulses: ImpulseRuntime?
    public var imageSpaceSwap = ExplosionImageSpaceSwap()
    /// Placed objects the session could not put into the world.
    private(set) var skippedPlacements = 0

    public init(
        records: EffectRecordStore = .empty,
        itemPlugin: String = "Skyrim.esm",
        world: (any ExplosionWorld)? = nil
    ) {
        self.records = records
        self.itemPlugin = itemPlugin
        self.world = world
    }

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
        cause: ExplosionCause,
        origin: ExplosionOrigin = ExplosionOrigin()
    ) -> ExplosionReport {
        detonationTotal += 1
        let radius = spec.radius
        let (damaged, shielded) = damage(spec, at: position, origin: origin)
        let broken = damageObjects(spec, at: position, origin: origin)
        for sound in spec.sounds {
            world?.playExplosionSound(sound, at: position)
        }
        if let model = spec.model {
            world?.showExplosionModel(model, at: position)
        }
        if let light = spec.light {
            world?.showExplosionLight(light, at: position)
        }
        if let dataSet = spec.impactDataSet {
            world?.playExplosionImpact(dataSet, at: position)
        }
        push(spec, radius: radius, at: position, source: origin.struck)
        let strength = startImageSpace(spec, at: position)
        let swapped = startImageSpaceSwap(spec, at: position)
        let (hazard, thrown) = place(spec, at: position)
        let objectPlaced = placeObject(spec, at: position, origin: origin)
        var report = ExplosionReport(
            name: spec.name, cause: cause, position: position, damaged: damaged,
            soundsPlayed: world == nil ? 0 : spec.sounds.count, imageSpaceStrength: strength,
            hazardPlaced: hazard, debrisThrown: thrown
        )
        report.swapApplied = swapped
        report.shielded = shielded
        report.objectsDamaged = broken
        report.objectPlaced = objectPlaced
        reports.append(report)
        if reports.count > Self.reportLimit {
            reports.removeFirst(reports.count - Self.reportLimit)
        }
        return report
    }

    /// Throws pieces of one DEBR record at `position`: the blast's six, or `count`.
    @discardableResult
    public func throwDebris(
        _ key: ReferenceKey, at position: SIMD3<Float>, force: Float, count: Int? = nil
    ) -> Int {
        guard let record = records.debris.record(key)?.record else { return 0 }
        seed &+= 1
        let pieces = DebrisSelection.launch(
            record.models, from: position, force: force, seed: seed,
            count: count ?? DebrisSelection.pieceCount
        )
        debris += pieces
        return pieces.count
    }

    /// Advances the debris and drops the pieces whose time ran out.
    public func advance(_ seconds: Float) {
        guard !debris.isEmpty else { return }
        debris = DebrisSelection.step(debris, seconds: seconds)
    }

    /// Health off each actor in reach, scaled by the shooter's skill. The shooter takes
    /// none, and an actor behind a wall none unless the blast ignores line of sight.
    private func damage(
        _ spec: ExplosionSpec, at position: SIMD3<Float>, origin: ExplosionOrigin
    ) -> (damaged: [ReferenceKey: Float], shielded: [ReferenceKey]) {
        guard spec.damage > 0, let world else { return ([:], []) }
        let scale = ExplosionSkill.scale(skill: origin.skill, isPlayer: origin.shooter == .player)
        let start = ExplosionSight.start(center: position, direction: origin.direction)
        var damaged: [ReferenceKey: Float] = [:]
        var shielded: [ReferenceKey] = []
        for target in world.explosionTargets() where target.key != origin.shooter {
            let amount = ExplosionFalloff.damage(
                spec.damage, radius: spec.radius, distance: Self.distance(position, target)
            ) * scale
            guard amount > 0 else { continue }
            if !spec.ignoresLineOfSight {
                let centre = target.feet + SIMD3(0, 0, target.capsule.height / 2)
                let end = target.key == .player ? world.explosionViewer() ?? centre : centre
                let hit = world.explosionObstruction(from: start, to: end)
                if ExplosionSight.blocks(hitDistance: hit, direction: origin.direction) {
                    shielded.append(target.key)
                    continue
                }
            }
            if world.applyExplosionDamage(amount, to: target.key) {
                damaged[target.key] = amount
            }
        }
        return (damaged, shielded)
    }

    /// Destruction damage on each destructible object in the radius: the blast's damage
    /// times its falloff and the shooter's skill.
    private func damageObjects(
        _ spec: ExplosionSpec, at position: SIMD3<Float>, origin: ExplosionOrigin
    ) -> [ReferenceKey: Float] {
        guard spec.damage > 0, spec.radius > 0, let world else { return [:] }
        let scale = ExplosionSkill.scale(skill: origin.skill, isPlayer: origin.shooter == .player)
        var damaged: [ReferenceKey: Float] = [:]
        for object in world.explosionObjects(within: spec.radius, of: position) {
            let amount = ExplosionFalloff.damage(
                spec.damage, radius: spec.radius, distance: simd_distance(object.feet, position)
            ) * scale
            if amount > 0, world.applyDestructionDamage(amount, to: object.key) {
                damaged[object.key] = amount
            }
        }
        return damaged
    }

    /// A placed object that is neither a hazard nor debris becomes a new reference.
    private func placeObject(
        _ spec: ExplosionSpec, at position: SIMD3<Float>, origin: ExplosionOrigin
    ) -> Bool {
        guard case let .other(base, _) = spec.placement else { return false }
        let placement = ExplosionObjectPlacement(
            base: base, position: position, location: origin.location,
            rotation: ExplosionObjectPlacement.rotation(facing: origin.direction),
            ownerSource: origin.owner ?? origin.shooter
        )
        guard world?.placeExplosionObject(placement) == true else {
            skippedPlacements += 1
            return false
        }
        return true
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

    /// The fixed modifier at full strength when the blast is close enough.
    private func startImageSpaceSwap(_ spec: ExplosionSpec, at position: SIMD3<Float>) -> Bool {
        guard let world else { return false }
        let viewer = world.explosionViewer() ?? position
        let power = ExplosionFalloff.swapPower(
            radius: spec.radius, distance: simd_distance(viewer, position)
        )
        guard
            imageSpaceSwap.applies(power: power, ignored: spec.ignoresImageSpaceSwap),
            let modifier = imageSpaceSwap.modifier
        else { return false }
        world.startExplosionImageSpace(modifier, strength: 1)
        return true
    }

    private func place(_ spec: ExplosionSpec, at position: SIMD3<Float>) -> (Bool, Int) {
        switch spec.placement {
        case let .hazard(key):
            (world?.placeExplosionHazard(key, at: position) ?? false, 0)
        case let .debris(key):
            (false, throwDebris(key, at: position, force: spec.force))
        case .other:
            (false, 0)
        case nil:
            (false, 0)
        }
    }

    /// From the blast center to the nearest point of the target's capsule axis.
    static func distance(_ center: SIMD3<Float>, _ target: MeleeTarget) -> Float {
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
        var spec = ExplosionSpec(
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
        spec.light = records.resolve(data?.light, from: resolved)
        spec.impactDataSet = records.resolve(data?.impactDataSet, from: resolved)
        spec.knockdown = ExplosionKnockdown(flags: data?.flags)
        spec.ignoresImageSpaceSwap = (data?.flags ?? 0) & Self.ignoreSwapFlag != 0
        spec.soundLevel = data?.soundLevel
        spec.ignoresLineOfSight = (data?.flags ?? 0) & Self.ignoreLineOfSightFlag != 0
        spec.verticalOffset = Self.clean(data?.verticalOffsetMultiplier)
        return spec
    }

    private static func clean(_ value: Float?) -> Float {
        guard let value, value.isFinite else { return 0 }
        return max(value, 0)
    }
}
