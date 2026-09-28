// The impact sound a landed swing plays (issue #195, roadmap item 15.4, scope
// point 7).
//
// This is the footstep chain with one link changed, and reusing it rather than
// building a second one is the point:
//
//   footstep: graph event -> FSTP tag -> IPDS -> IPCT for the material -> SNDR
//   melee:    HitFrame    -> WEAP INAM -> IPDS -> IPCT for the material -> SNDR
//
// From the IPDS onwards the two are identical, so `ImpactDataSet.impact(for:)`
// and `Impact.sound` do the work here exactly as they do for a footstep, and
// the material argument means the same thing: the MATT type of the surface that
// was struck. `WalkController.groundMaterial` reports it for a foot; for a hit
// the caller supplies the target's material, which in this milestone is the
// ground material under the target — actors carry no per-body-part material in
// this engine yet, and saying so is better than inventing one.
//
// Every link is optional, on the same reasoning the footstep store gives: a
// weapon with no INAM, an IPDS with no entry for the material, an IPCT with no
// sound. Each ends the walk with nil and a silent hit, never a throw. Vanilla
// has silent combinations of its own, so a missing link is data rather than a
// fault.
//
// Decals and visual effects are explicitly out of this item's scope; only the
// sound is resolved.
//
// Documented in docs/engine/melee-combat.md.

import Foundation

/// What a resolved hit impact turns into. The melee counterpart of
/// `ResolvedFootstep`, and deliberately the same shape.
nonisolated struct ResolvedMeleeImpact: Equatable, Sendable {
    /// The IPDS the weapon named.
    let dataSet: FormID
    /// The IPCT chosen for the struck material.
    let impact: Impact
    /// The SNDR to play. Never null: a resolution with no sound is reported as
    /// nil instead.
    let sound: FormID
}

/// Walks a weapon's INAM to the sound one hit plays.
///
/// A thin reader over the record indexes `FootstepStore` already builds, so a
/// session that can play footsteps can play hit impacts with no second load.
nonisolated struct MeleeImpactResolver {
    private let impactDataSets: [UInt32: ImpactDataSet]
    private let impacts: [UInt32: Impact]

    /// Reads the indexes straight off the footstep store, which is where IPDS
    /// and IPCT already live.
    init(footsteps: FootstepStore) {
        impactDataSets = footsteps.impactDataSets
        impacts = footsteps.impacts
    }

    /// Test seam: indexes built from decoded values rather than from a file.
    init(impactDataSets: [ImpactDataSet], impacts: [Impact]) {
        self.impactDataSets = Dictionary(
            uniqueKeysWithValues: impactDataSets.map { ($0.formID.rawValue, $0) }
        )
        self.impacts = Dictionary(
            uniqueKeysWithValues: impacts.map { ($0.formID.rawValue, $0) }
        )
    }

    /// The sound `weapon` plays when it lands on `material`, or nil where any
    /// link in the chain is missing.
    ///
    /// - Parameters:
    ///   - weapon: the swing profile; its `impactDataSet` is the WEAP INAM.
    ///   - material: the MATT type of what was struck, or nil when it names
    ///     none — the impact table then answers with its representative entry,
    ///     exactly as it does for a footstep on an unnamed surface.
    func resolve(weapon: MeleeWeaponProfile, material: FormID?) -> ResolvedMeleeImpact? {
        guard
            let dataSetID = weapon.impactDataSet,
            let dataSet = impactDataSets[dataSetID.rawValue],
            let impactID = dataSet.impact(for: material),
            let impact = impacts[impactID.rawValue],
            let sound = impact.sound
        else { return nil }
        return ResolvedMeleeImpact(dataSet: dataSetID, impact: impact, sound: sound)
    }
}
