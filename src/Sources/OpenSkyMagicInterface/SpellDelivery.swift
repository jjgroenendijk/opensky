// Delivery values: https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF
// (docs/engine/spell-delivery.md).

public import OpenSkyFormatsESM

/// Which deliveries this build carries out.
nonisolated public enum SpellDelivery: Sendable {
    /// Whether a cast of `delivery` runs rather than being refused.
    ///
    /// `castingType` decides for the deliveries whose two casting shapes are
    /// not equally implementable; a nil header reads as self delivery, which is
    /// the same fallback the cost calculation takes.
    public static func isImplemented(
        _ delivery: MagicEffectDelivery,
        castingType: MagicEffectCastingType?
    ) -> Bool {
        switch delivery {
        case .selfTarget, .aimed, .touch: true
        case .targetActor, .targetLocation: castingType != .concentration
        case .unknown: false
        }
    }
}
