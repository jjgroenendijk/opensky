public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface

extension PapyrusWorldStateBridgePort {
    @discardableResult
    public func runPerkFragment(
        of perk: Perk,
        key: ReferenceKey,
        index: UInt16,
        activation: PerkFragmentActivation
    ) -> Bool {
        perkFragments.runPerkFragment(of: perk, key: key, index: index, activation: activation)
    }
}
