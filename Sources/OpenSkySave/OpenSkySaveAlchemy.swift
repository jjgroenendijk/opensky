// CPOT, INGK, and WPSN chunks: brewed potions, known ingredient effects, and weapon
// poisons, each merged into the `RDLT` deltas by key. Rows ascend by FormID, so equal
// state gives equal bytes. Layout: docs/formats/opensky-save-actor-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// Per potion: FormID, name, poison byte, value, then each effect's MGEF,
    /// magnitude, area, and duration.
    public static func writeCreatedPotions(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            CreatedPotionState.self, tag: OpenSkySaveFormat.ChunkTag.createdPotions,
            entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.potions.count))
            for potion in state.potions {
                payload.writeUInt32(potion.id.rawValue)
                writeString(potion.name, into: &payload)
                payload.writeUInt8(potion.isPoison ? 1 : 0)
                payload.writeUInt32(UInt32(bitPattern: potion.value))
                payload.writeUInt32(UInt32(clamping: potion.effects.count))
                for effect in potion.effects {
                    payload.writeUInt32(effect.effect.rawValue)
                    payload.writeFloat32(effect.magnitude)
                    payload.writeUInt32(effect.area)
                    payload.writeUInt32(effect.duration)
                }
            }
        }
    }

    /// Per ingredient: its FormID and one byte with a bit per known effect.
    public static func writeIngredientKnowledge(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            IngredientKnowledgeState.self, tag: OpenSkySaveFormat.ChunkTag.ingredientKnowledge,
            entries, &writer
        ) { state, payload in
            let rows = state.known.sorted { $0.key.rawValue < $1.key.rawValue }
            payload.writeUInt32(UInt32(clamping: rows.count))
            for (ingredient, mask) in rows {
                payload.writeUInt32(ingredient.rawValue)
                payload.writeUInt8(mask)
            }
        }
    }

    /// Per weapon: its FormID, the poison's FormID, and the doses left.
    public static func writeWeaponPoisons(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            WeaponPoisonState.self, tag: OpenSkySaveFormat.ChunkTag.weaponPoisons,
            entries, &writer
        ) { state, payload in
            let rows = state.poisons.sorted { $0.key.rawValue < $1.key.rawValue }
            payload.writeUInt32(UInt32(clamping: rows.count))
            for (weapon, poison) in rows {
                payload.writeUInt32(weapon.rawValue)
                payload.writeUInt32(poison.poison.rawValue)
                payload.writeUInt32(UInt32(bitPattern: poison.doses))
            }
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeCreatedPotions(
        _ payload: Data
    ) throws -> [SaveStoryEntry<CreatedPotionState>] {
        let tag = OpenSkySaveFormat.ChunkTag.createdPotions
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumAlchemyEntrySize
        ) { reader in
            let count = try reader.uint32("CPOT potion count")
            try validate(count, OpenSkySaveFormat.minimumCreatedPotionSize, reader, tag)
            var potions: [CreatedPotion] = []
            for _ in 0 ..< count {
                try potions.append(decodePotion(&reader, tag: tag))
            }
            return CreatedPotionState(potions: potions)
        }
    }

    public static func decodeIngredientKnowledge(
        _ payload: Data
    ) throws -> [SaveStoryEntry<IngredientKnowledgeState>] {
        let tag = OpenSkySaveFormat.ChunkTag.ingredientKnowledge
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumAlchemyEntrySize
        ) { reader in
            let count = try reader.uint32("INGK row count")
            try validate(count, OpenSkySaveFormat.ingredientKnowledgeRowSize, reader, tag)
            var known: [FormID: UInt8] = [:]
            for _ in 0 ..< count {
                let ingredient = try FormID(reader.uint32("INGK ingredient"))
                known[ingredient] = try reader.uint8("INGK effects")
            }
            return IngredientKnowledgeState(known: known)
        }
    }

    public static func decodeWeaponPoisons(
        _ payload: Data
    ) throws -> [SaveStoryEntry<WeaponPoisonState>] {
        let tag = OpenSkySaveFormat.ChunkTag.weaponPoisons
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumAlchemyEntrySize
        ) { reader in
            let count = try reader.uint32("WPSN row count")
            try validate(count, OpenSkySaveFormat.weaponPoisonRowSize, reader, tag)
            var poisons: [FormID: WeaponPoison] = [:]
            for _ in 0 ..< count {
                let weapon = try FormID(reader.uint32("WPSN weapon"))
                poisons[weapon] = try WeaponPoison(
                    poison: FormID(reader.uint32("WPSN poison")),
                    doses: Int32(bitPattern: reader.uint32("WPSN doses"))
                )
            }
            return WeaponPoisonState(poisons: poisons)
        }
    }

    private static func decodePotion(_ reader: inout SaveReader, tag: String) throws
        -> CreatedPotion
    {
        let id = try FormID(reader.uint32("CPOT FormID"))
        let name = try reader.string("CPOT name")
        let isPoison = try reader.bool("CPOT poison")
        let value = try Int32(bitPattern: reader.uint32("CPOT value"))
        let count = try reader.uint32("CPOT effect count")
        try validate(count, OpenSkySaveFormat.createdPotionEffectSize, reader, tag)
        var effects: [CreatedPotionEffect] = []
        for _ in 0 ..< count {
            try effects.append(CreatedPotionEffect(
                effect: FormID(reader.uint32("CPOT effect")),
                magnitude: reader.float32("CPOT magnitude"),
                area: reader.uint32("CPOT area"),
                duration: reader.uint32("CPOT duration")
            ))
        }
        return CreatedPotion(id: id, name: name, isPoison: isPoison, value: value, effects: effects)
    }

    private static func validate(
        _ count: UInt32, _ size: Int, _ reader: SaveReader, _ tag: String
    ) throws {
        try OpenSkySaveDecoder.validate(
            count: count, minimumElementSize: size, remaining: reader.bytesRemaining, chunk: tag
        )
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// False when `tag` is none of the player item chunks.
    static func applyPlayerItems(tag: String, payload: Data, to body: inout Body) throws -> Bool {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.createdPotions:
            body.createdPotions = try OpenSkySaveStoryDecoder.decodeCreatedPotions(payload)
        case OpenSkySaveFormat.ChunkTag.ingredientKnowledge:
            body.ingredientKnowledge = try OpenSkySaveStoryDecoder
                .decodeIngredientKnowledge(payload)
        case OpenSkySaveFormat.ChunkTag.weaponPoisons:
            body.weaponPoisons = try OpenSkySaveStoryDecoder.decodeWeaponPoisons(payload)
        case OpenSkySaveFormat.ChunkTag.favourites:
            body.favourites = try OpenSkySaveStoryDecoder.decodeFavourites(payload)
        case OpenSkySaveFormat.ChunkTag.enchanting:
            body.enchanting = try OpenSkySaveStoryDecoder.decodeEnchanting(payload)
        default:
            return false
        }
        return true
    }

    /// `CPOT`, `INGK`, `WPSN`, `FAVS`, `PRUL`, and `ENCK`: state of the player and its items.
    static func mergePlayerState(
        _ body: Body,
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        var entries = OpenSkySaveDeltaMerge.merge(body.createdPotions, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.ingredientKnowledge, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.weaponPoisons, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.favourites, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.playerRules, into: entries)
        return OpenSkySaveDeltaMerge.merge(body.enchanting, into: entries)
    }
}
