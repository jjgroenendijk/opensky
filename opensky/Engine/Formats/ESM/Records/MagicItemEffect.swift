// The effect list shared by every "magic item" record — ALCH and INGR here,
// with ENCH/SPEL/SCRL using the same shape when a later milestone needs them.
// An effect is a run of subrecords, not a struct: EFID names the MGEF, the
// EFIT that follows carries its numbers, and any CTDA fields after that are
// conditions on that one effect. The run repeats once per effect.
//
//   EFID  4 bytes   FormID -> MGEF (base effect)
//   EFIT 12 bytes   float32 magnitude, uint32 area, uint32 duration
//   CTDA 32 bytes   condition on the effect (see Condition.swift)
//
// Scope note (issue #175): effects decode as *links* only. Magic-effect
// semantics — what an MGEF actually does, and the auto-calc cost formula UESP
// documents alongside EFIT — belong to the magic milestone, not here.
//
// Decode policy: an EFIT without a preceding EFID has nothing to attach to and
// is dropped; an EFID whose EFIT never arrives still yields an entry with zero
// magnitude/area/duration, because the MGEF link is the part the inventory
// runtime needs and vanilla always writes the pair. Neither case throws.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ALCH" and ".../INGR" Effect tables
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ALCH
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: `wbEFID` (line 3832),
//   `wbEFIT` (3834), `wbEffect` (4030).
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct MagicItemEffect: Equatable {
    /// EFID — the MGEF this entry applies. Decoded as a link; no semantics.
    let effect: FormID
    /// EFIT magnitude. Units are per-MGEF and are not interpreted here.
    let magnitude: Float
    /// EFIT area of effect, 0 for a point effect.
    let area: UInt32
    /// EFIT duration in seconds, 0 for instantaneous.
    let duration: UInt32
    /// CTDA conditions gating this effect, in file order. Decoded through the
    /// shared `ConditionList` so CITC counts and CIS1/CIS2 parameter-name
    /// overrides behave exactly as they do everywhere else.
    let conditions: ConditionList
}

/// Mutable accumulator that folds the EFID/EFIT/CTDA run into entries. A
/// record's field switch forwards every field it does not own; `finish()`
/// flushes the effect still being built when the record ends.
nonisolated struct MagicItemEffectList {
    private var effects: [MagicItemEffect] = []
    private var pendingEffect: FormID?
    private var pendingMagnitude: Float = 0
    private var pendingArea: UInt32 = 0
    private var pendingDuration: UInt32 = 0
    private var pendingConditions = ConditionList()

    init() {}

    /// Decodes `field` when it belongs to the effect run and reports whether
    /// it was consumed.
    mutating func decode(field: ESMField) throws -> Bool {
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
    mutating func finish() -> [MagicItemEffect] {
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
