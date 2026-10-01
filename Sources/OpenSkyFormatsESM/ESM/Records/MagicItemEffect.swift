// The effect list of magic item records: a repeated EFID, EFIT, CTDA run. An
// EFIT without an EFID is dropped; an EFID without an EFIT gets zero values,
// because the MGEF link is what matters. Neither case throws.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MagicItemEffect: Equatable, Sendable {
    /// EFID — the MGEF this entry applies; resolved through MagicEffectStore.
    public let effect: FormID
    /// EFIT magnitude. Units are per-MGEF and are not interpreted here.
    public let magnitude: Float
    /// EFIT area of effect, 0 for a point effect.
    public let area: UInt32
    /// EFIT duration in seconds, 0 for instantaneous.
    public let duration: UInt32
    /// CTDA conditions gating this effect, in file order. Decoded through the
    /// shared `ConditionList` so CITC counts and CIS1/CIS2 parameter-name
    /// overrides behave exactly as they do everywhere else.
    public let conditions: ConditionList

    /// A copy of this entry with its magnitude multiplied, for one
    /// resistance-scaled application. The decoded record stays unchanged.
    public func scalingMagnitude(by multiplier: Float) -> MagicItemEffect {
        guard multiplier.isFinite else { return self }
        return MagicItemEffect(
            effect: effect,
            magnitude: max(0, magnitude * multiplier),
            area: area,
            duration: duration,
            conditions: conditions
        )
    }
}

/// Mutable accumulator that folds the EFID/EFIT/CTDA run into entries. A
/// record's field switch forwards every field it does not own; `finish()`
/// flushes the effect still being built when the record ends.
nonisolated public struct MagicItemEffectList: Sendable {
    private var effects: [MagicItemEffect] = []
    private var pendingEffect: FormID?
    private var pendingMagnitude: Float = 0
    private var pendingArea: UInt32 = 0
    private var pendingDuration: UInt32 = 0
    private var pendingConditions = ConditionList()

    public init() {}

    /// Decodes `field` when it belongs to the effect run and reports whether
    /// it was consumed.
    public mutating func decode(field: ESMField) throws -> Bool {
        switch field.type {
        case "EFID":
            flush()
            pendingEffect = try InventoryItemFields.optionalFormID(field)
        case "EFIT":
            guard pendingEffect != nil, field.data.count >= 12 else { return true }
            var reader = BinaryReader(field.data)
            pendingMagnitude = try reader.readFloat32()
            pendingArea = try reader.readUInt32()
            pendingDuration = try reader.readUInt32()
        default:
            // Conditions only belong to an effect once an EFID has opened one;
            // a record-level condition run before the first EFID is not ours.
            guard pendingEffect != nil else { return false }
            return try pendingConditions.decode(field: field)
        }
        return true
    }

    /// Flushes the effect under construction and returns every entry in file
    /// order. Call once, after the record's field loop.
    public mutating func finish() -> [MagicItemEffect] {
        flush()
        return effects
    }

    private mutating func flush() {
        guard let pendingEffect else { return }
        effects.append(
            MagicItemEffect(
                effect: pendingEffect,
                magnitude: pendingMagnitude,
                area: pendingArea,
                duration: pendingDuration,
                conditions: pendingConditions
            )
        )
        self.pendingEffect = nil
        pendingMagnitude = 0
        pendingArea = 0
        pendingDuration = 0
        pendingConditions = ConditionList()
    }
}
