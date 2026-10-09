// Footstep records and tag -> sound resolution. The chain one step walks:
// graph event ("FootLeft") -> FSTP with that ANAM tag in the gait's FSTS list
// -> IPDS -> IPCT for the surface -> SNDR. ARMA.SNDD on the foot armature picks
// the FSTS. A missing link ends the walk with nil, because vanilla fires far
// more footstep events than it has sounds for.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// What a resolved footstep event turns into.
nonisolated public struct ResolvedFootstep: Equatable, Sendable {
    public let footstep: Footstep
    public let impact: Impact
    /// A resolution with no sound is nil instead, so this is never null.
    public let sound: FormID
}

nonisolated public final class FootstepStore {
    /// The set for an actor with no boot armature. Vanilla has one (`00012F16`).
    public static let defaultSetEditorID = "DefaultFootstepSet"

    public let sets: [UInt32: FootstepSet]
    public let footsteps: [UInt32: Footstep]
    public let impactDataSets: [UInt32: ImpactDataSet]
    public let impacts: [UInt32: Impact]
    /// ARMA FormID -> FSTS FormID, from ARMA.SNDD, for armatures that name one.
    public let armatureSets: [UInt32: FormID]
    public let skippedRecords: SkippedRecords

    /// Nil when the plugin has no set named `defaultSetEditorID`.
    public private(set) var defaultSet: FootstepSet?

    public convenience init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

    public init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        sets = loadOrder.indexRecords(of: "FSTS", skipped: &skipped) { try FootstepSet(record: $0) }
        footsteps = loadOrder
            .indexRecords(of: "FSTP", skipped: &skipped) { try Footstep(record: $0) }
        impactDataSets = loadOrder.indexRecords(of: "IPDS", skipped: &skipped) {
            try ImpactDataSet(record: $0)
        }
        impacts = loadOrder.indexRecords(of: "IPCT", skipped: &skipped) { try Impact(record: $0) }
        armatureSets = loadOrder.indexRecords(of: "ARMA", skipped: &skipped) {
            try ArmorAddon(record: $0).footstepSound
        }
        skippedRecords = skipped
        defaultSet = sets.values.first { $0.editorID == Self.defaultSetEditorID }
    }

    /// Test seam: built from decoded values rather than from a file.
    public init(
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
        skippedRecords = SkippedRecords()
        defaultSet = sets.first { $0.editorID == Self.defaultSetEditorID }
    }

    public func set(_ id: FormID) -> FootstepSet? {
        sets[id.rawValue]
    }

    /// The set of the first armature that names one, else `defaultSet`. Callers
    /// pass the feet-slot armatures, boot before skin.
    public func set(forArmatures armatures: [FormID]) -> FootstepSet? {
        for armature in armatures {
            if let id = armatureSets[armature.rawValue], let set = set(id) {
                return set
            }
        }
        return defaultSet
    }

    /// Walks one graph event name to its sound. `material` is the MATT under
    /// the foot; nil makes the impact table use its representative entry.
    public func resolve(
        tag: String,
        gait: FootstepGait,
        in set: FootstepSet,
        material: FormID? = nil
    ) -> ResolvedFootstep? {
        // No vanilla humanoid set repeats a tag in one gait, so the first wins.
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

    /// Every tag one gait of a set answers to, in record order.
    public func tags(for gait: FootstepGait, in set: FootstepSet) -> [String] {
        set.footsteps(for: gait).compactMap { footsteps[$0.rawValue]?.tag }
    }
}
