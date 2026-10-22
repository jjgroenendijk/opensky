// One "Add Activate Choice" effect of the Activate entry point: a button the use key
// offers on a target, and the perk fragment it runs. CK wiki "Perk Fragments" and
// "Perk Entry Point". Layout: docs/formats/perks.md. Rules: docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct PerkActivateChoice: Sendable {
    /// `EPF2`. Nil for a run-immediately choice, which shows no button.
    public let label: LString?
    public let runsImmediately: Bool
    public let replacesDefault: Bool
    /// The `EPF3` fragment index, or nil when the effect carries no `EPF3`.
    public let fragmentIndex: UInt16?
    /// The perk that carries the effect; nil for a fake built in a test.
    public let perk: ResolvedPerk?

    public init(effect: PerkEffect, perk: ResolvedPerk?) {
        label = effect.buttonLabel
        let options = effect.scriptFlags?.options ?? []
        runsImmediately = options.contains(.runImmediately)
        replacesDefault = options.contains(.replaceDefault)
        fragmentIndex = effect.scriptFlags?.fragmentIndex
        self.perk = perk
    }

    public init(
        label: LString?,
        runsImmediately: Bool = false,
        replacesDefault: Bool = false,
        fragmentIndex: UInt16? = nil
    ) {
        self.label = label
        self.runsImmediately = runsImmediately
        self.replacesDefault = replacesDefault
        self.fragmentIndex = fragmentIndex
        perk = nil
    }

    /// The perk's `VMAD` fragment this choice runs. Nil when the perk has none at the index.
    public var fragment: ScriptFragment? {
        guard let fragmentIndex else { return nil }
        return perk?.record.script.recordFragments?.fragment(slot: UInt32(fragmentIndex))
    }

    public var perkKey: ReferenceKey? {
        perk.map { ReferenceKey(resolved: $0.id) }
    }
}
