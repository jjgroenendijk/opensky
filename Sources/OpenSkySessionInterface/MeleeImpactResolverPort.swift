public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `MeleeImpactResolver`.
public protocol MeleeImpactResolverPort {
    func resolve(weapon: MeleeWeaponProfile, material: FormID?) -> ResolvedMeleeImpact?
    func resolve(dataSet dataSetID: FormID, material: FormID?) -> ResolvedMeleeImpact?
}
