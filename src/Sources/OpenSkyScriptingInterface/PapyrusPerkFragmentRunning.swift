public import OpenSkyFormatsESM

/// Runs one fragment of a perk's fragment script, for an Activate choice of the perk.
public protocol PapyrusPerkFragmentRunning {
    @discardableResult func runPerkFragment(
        of perk: Perk,
        key: ReferenceKey,
        index: UInt16,
        activation: PerkFragmentActivation
    ) -> Bool
}
