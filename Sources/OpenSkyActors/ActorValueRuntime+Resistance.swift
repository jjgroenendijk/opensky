import OpenSkyActorsInterface
import OpenSkyGameData

extension ActorValueRuntime {
    /// The fraction of incoming damage `holder`'s resistance at `index`
    /// removes, capped.
    ///
    /// - Returns: nil when `index` is not a percentage resistance, which
    ///   includes `Damage Resist` and every non-resistance actor value. A
    ///   caller that gets nil has an effect whose resistance the armor formula
    ///   or no formula at all answers, and must not treat it as zero
    ///   resistance without saying so.
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

    /// What one point of magic damage of `element`'s school is multiplied by
    /// before it reaches `holder`: Resist Magic first, then the element's own
    /// resistance, exactly as UESP states the order.
    ///
    /// - Parameter element: the MGEF's resistance actor value, or nil for an
    ///   effect that names none. A `nil` element still pays Resist Magic, which
    ///   is what makes a school-less magic effect resistible at all.
    /// - Returns: 1 when nothing resists, 0 when the actor is immune, and above
    ///   1 for a weakness — a negative resistance multiplies damage up, and two
    ///   weaknesses compound, which is what UESP's "Weakness to fire is
    ///   strengthened by weakness to magic" describes
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
