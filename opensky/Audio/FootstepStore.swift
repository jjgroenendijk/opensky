// Footstep record index and tag -> sound resolution (issue #352).
//
// The chain a footstep travels, and why each link exists:
//
//   behavior-graph event ("FootLeft")
//     -> FSTP whose ANAM tag matches, inside the FSTS list for this gait
//     -> IPDS the footstep names
//     -> IPCT for the surface under the foot
//     -> SNDR the impact plays
//
// The set itself comes from the armature on the actor's feet: ARMA.SNDD names
// an FSTS, so barefoot, light boots, and heavy boots each sound different
// without the engine choosing anything. An actor whose feet resolve to no
// armature falls back to `DefaultFootstepSet`.
//
// Every link is optional. A tag with no matching footstep, a footstep with no
// impact data set, an impact with no sound: each ends the walk with nil and a
// silent step, never a throw. Vanilla raises footstep events far more often
// than it has sounds for them (the graph fires `FootLeft2` and `FootRight3`
// for actors whose set names neither), so a missing link is normal data rather
// than a fault.

import Foundation

/// What a resolved footstep event turns into.
nonisolated struct ResolvedFootstep: Equatable, Sendable {
    /// The FSTP that matched the tag.
    let footstep: Footstep
    /// The IPCT chosen for the surface.
    let impact: Impact
    /// The SNDR to play. Never null: a resolution with no sound is reported as
    /// nil instead.
    let sound: FormID
}

nonisolated final class FootstepStore {
    /// Editor ID of the set an actor with no boot armature walks with. Vanilla
    /// names exactly one FSTS this way (`00012F16`); a load order that does not
    /// leaves `defaultSet` nil and the player silent until an armature
    /// resolves, which is visible in the readout rather than guessed around.
    static let defaultSetEditorID = "DefaultFootstepSet"

    let sets: [UInt32: FootstepSet]
    let footsteps: [UInt32: Footstep]
    let impactDataSets: [UInt32: ImpactDataSet]
    let impacts: [UInt32: Impact]
    /// ARMA FormID -> FSTS FormID, from ARMA.SNDD. Only the armatures that
    /// declare a footstep set appear.
    let armatureSets: [UInt32: FormID]

    /// The set named by `defaultSetEditorID`, or nil when the plugin has none.
    private(set) var defaultSet: FootstepSet?

    init(file: ESMFile) {
        sets = Self.index(file, type: "FSTS") { try? FootstepSet(record: $0) }
        footsteps = Self.index(file, type: "FSTP") { try? Footstep(record: $0) }
        impactDataSets = Self.index(file, type: "IPDS") { try? ImpactDataSet(record: $0) }
        impacts = Self.index(file, type: "IPCT") { try? Impact(record: $0) }
        armatureSets = Self.index(file, type: "ARMA") {
            (try? ArmorAddon(record: $0))?.footstepSound
        }
        defaultSet = sets.values.first { $0.editorID == Self.defaultSetEditorID }
    }

    /// Test seam: an index built from decoded values rather than from a file.
    init(
        sets: [FootstepSet],
        footsteps: [Footstep],
        impactDataSets: [ImpactDataSet],
        impacts: [Impact],
        armatureSets: [FormID: FormID] = [:]
    ) {
        self.sets = Dictionary(
            uniqueKeysWithValues: sets.map { ($0.formID.rawValue, $0) }
        )
        self.footsteps = Dictionary(
            uniqueKeysWithValues: footsteps.map { ($0.formID.rawValue, $0) }
        )
        self.impactDataSets = Dictionary(
            uniqueKeysWithValues: impactDataSets.map { ($0.formID.rawValue, $0) }
        )
        self.impacts = Dictionary(
            uniqueKeysWithValues: impacts.map { ($0.formID.rawValue, $0) }
        )
        self.armatureSets = Dictionary(
            uniqueKeysWithValues: armatureSets.map { ($0.key.rawValue, $0.value) }
        )
        defaultSet = sets.first { $0.editorID == Self.defaultSetEditorID }
    }

    func set(_ id: FormID) -> FootstepSet? {
        sets[id.rawValue]
    }

    /// The footstep set for the first of `armatures` that declares one, in the
    /// order given, falling back to `defaultSet`. Callers pass the armatures on
    /// the actor's feet slot; passing several keeps the choice between a boot
    /// and the skin under it out of this type.
    func set(forArmatures armatures: [FormID]) -> FootstepSet? {
        for armature in armatures {
            if let id = armatureSets[armature.rawValue], let set = set(id) {
                return set
            }
        }
        return defaultSet
    }

    /// Walks one graph event name to the sound it should play.
    ///
    /// `material` is the MATT type of the surface under the foot when the
    /// caller knows it. Nothing knows it yet — OpenSky's collision world
    /// carries no per-triangle Havok material, which is issue #358 — so the
    /// impact table answers with its representative entry
    /// (`ImpactDataSet.impact(for:)`).
    func resolve(
        tag: String,
        gait: FootstepGait,
        in set: FootstepSet,
        material: FormID? = nil
    ) -> ResolvedFootstep? {
        // Record order decides between two footsteps carrying the same tag.
        // UESP describes a set as alternating its footsteps; no vanilla
        // humanoid set repeats a tag within one gait, so there is nothing to
        // alternate and taking the first is the whole behavior.
        for id in set.footsteps(for: gait) {
            guard
                let footstep = footsteps[id.rawValue],
                footstep.tag?.caseInsensitiveCompare(tag) == .orderedSame
            else { continue }
            guard
                let dataSetID = footstep.impactDataSet,
                let dataSet = impactDataSets[dataSetID.rawValue],
                let impactID = dataSet.impact(for: material),
                let impact = impacts[impactID.rawValue],
                let sound = impact.sound
            else { return nil }
            return ResolvedFootstep(footstep: footstep, impact: impact, sound: sound)
        }
        return nil
    }

    /// Every tag one gait of a set can answer to, in record order. Drives the
    /// panel readout and lets the director drop an event without walking the
    /// whole chain for it.
    func tags(for gait: FootstepGait, in set: FootstepSet) -> [String] {
        set.footsteps(for: gait).compactMap { footsteps[$0.rawValue]?.tag }
    }

    private static func index<Value>(
        _ file: ESMFile,
        type: FourCC,
        decode: (ESMRecord) -> Value?
    ) -> [UInt32: Value] {
        var values: [UInt32: Value] = [:]
        guard let group = file.topGroup(of: type), let children = try? group.children() else {
            return values
        }
        for case let .record(record) in children where record.type == type {
            if let value = decode(record) {
                values[record.formID] = value
            }
        }
        return values
    }
}
