import OpenSkyGameData

extension ActorValueRuntime {
    /// The fraction of incoming damage `holder`'s resistance at `index` removes,
    /// capped.
    /// - Returns: nil when `index` is not a percentage resistance. The caller must
    ///   not treat nil as zero resistance.
    public func resistanceFraction(
        at index: Int32,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float? {
        guard
            ActorResistance.isPercentage(index: index),
            let points = value(at: index, on: holder)
        else { return nil }
        return ActorResistance.fraction(
            percentagePoints: points,
            at: index,
            isPlayer: holder.subject == .player,
            settings: settings
        )
    }

    /// What one point of magic damage of `element`'s school is multiplied by:
    /// Resist Magic first, then the element's resistance, in UESP's order.
    /// - Parameter element: the MGEF's resistance value; nil still pays Resist Magic.
    /// - Returns: 1 when nothing resists, 0 when immune, above 1 for a weakness
    ///   (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>).
    public func magicDamageMultiplier(
        element: Int32?,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float {
        let magic = resistanceFraction(
            at: ActorValueIndex.resistMagic,
            on: holder,
            settings: settings
        ) ?? 0
        let elemental = element.flatMap { index -> Float? in
            // Resist Magic is already applied; an effect that names it as its
            // own resistance must not pay it twice.
            guard index != ActorValueIndex.resistMagic else { return nil }
            return resistanceFraction(at: index, on: holder, settings: settings)
        } ?? 0
        return (1 - magic) * (1 - elemental)
    }
}
