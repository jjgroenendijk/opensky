// The impact a landed swing plays. It reuses the footstep chain with one link
// changed: WEAP INAM -> IPDS -> IPCT for the material -> SNDR. Every link is
// optional; a missing one gives a silent hit, never a throw. The IPCT also names
// the model and decal the hit leaves. See docs/engine/melee-combat.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import simd

/// What a resolved hit impact turns into. The melee counterpart of
/// `ResolvedFootstep`, and deliberately the same shape.
nonisolated public struct ResolvedMeleeImpact: Equatable, Sendable {
    /// The SNDR to play. Never null: a resolution with no sound is reported as
    /// nil instead.
    public let sound: FormID
    /// The IPCT, for its model and decal.
    public let impact: Impact?
    /// The actor struck, so a blood decal can find the ground under it.
    public var target: ReferenceKey?
    /// The struck surface's normal; nil for an actor.
    public var surfaceNormal: SIMD3<Float>?

    public init(
        sound: FormID,
        impact: Impact? = nil,
        target: ReferenceKey? = nil,
        surfaceNormal: SIMD3<Float>? = nil
    ) {
        self.sound = sound
        self.impact = impact
        self.target = target
        self.surfaceNormal = surfaceNormal
    }
}

/// Walks a weapon's INAM to the sound one hit plays.
///
/// A thin reader over the record indexes `FootstepStore` already builds, so a
/// session that can play footsteps can play hit impacts with no second load.
nonisolated public struct MeleeImpactResolver: Sendable {
    private let impactDataSets: [UInt32: ImpactDataSet]
    private let impacts: [UInt32: Impact]
    private let materialParents: MaterialParents

    /// Reads the indexes straight off the footstep store, which is where IPDS
    /// and IPCT already live.
    public init(footsteps: FootstepStore) {
        impactDataSets = footsteps.impactDataSets
        impacts = footsteps.impacts
        materialParents = footsteps.materialParents
    }

    /// The sound `weapon` plays when it lands on `material`, or nil where a link is
    /// missing.
    /// - Parameters:
    ///   - weapon: the swing profile; its `impactDataSet` is the WEAP INAM.
    ///   - material: the MATT type struck, tried with its parents, or nil for the
    ///     table's default entry.
    public func resolve(weapon: MeleeWeaponProfile, material: FormID?) -> ResolvedMeleeImpact? {
        guard
            let dataSetID = weapon.impactDataSet,
            let dataSet = impactDataSets[dataSetID.rawValue],
            let impactID = dataSet.impact(forFirstOf: materialParents.chain(from: material)),
            let impact = impacts[impactID.rawValue],
            let sound = impact.sound
        else { return nil }
        return ResolvedMeleeImpact(sound: sound, impact: impact)
    }
}
