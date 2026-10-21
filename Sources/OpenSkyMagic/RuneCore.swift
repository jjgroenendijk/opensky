// Runes as pure rules: where a target-location spell lands, how many runes a caster
// keeps, and which actor sets one off. UESP "Skyrim:Destruction": a rune is "cast on a
// surface and triggered like a proximity mine". See docs/engine/spell-delivery.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics

nonisolated public struct RuneSettings: Equatable, Sendable {
    /// `iMaxPlayerRunes`: how many runes the player keeps at once.
    public var maximumPlayerRunes = 1

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iMaxPlayerRunes", into: &settings, \.maximumPlayerRunes)
        return settings
    }
}

/// A rune waiting on the ground.
nonisolated public struct PlacedRune: Equatable, Sendable {
    public let payload: SpellPayload
    public let position: SIMD3<Float>
    /// How near an actor must come, world units.
    public let proximity: Float

    public init(payload: SpellPayload, position: SIMD3<Float>, proximity: Float) {
        self.payload = payload
        self.position = position
        self.proximity = proximity
    }
}

nonisolated public enum RuneCore {
    /// The keyword vanilla rune effects carry.
    public static let keyword = "MagicRune"
    /// `explosionProximity` of `RuneFireProjectile`, for a rune whose PROJ gives none.
    public static let defaultProximity: Float = 150

    /// A target-location spell's reach in world units. [WARNING] `SPIT` range is read as
    /// feet here: Fire Rune's range is 20, and 20 world units would be at the caster's feet.
    public static func reach(range: Float, settings: MagicAreaSettings = .documentedDefaults)
        -> Float
    {
        max(0, range) * max(0, settings.worldUnitsPerAreaUnit)
    }

    /// `runes` with `rune` added. Past the player's limit the oldest player rune goes.
    /// UESP names no limit for NPCs, so theirs is not capped.
    public static func placing(
        _ rune: PlacedRune, in runes: [PlacedRune], settings: RuneSettings
    ) -> [PlacedRune] {
        var placed = runes + [rune]
        guard rune.payload.caster == .player else { return placed }
        let limit = max(1, settings.maximumPlayerRunes)
        while placed.count(where: { $0.payload.caster == .player }) > limit {
            guard let oldest = placed.firstIndex(where: { $0.payload.caster == .player }) else {
                break
            }
            placed.remove(at: oldest)
        }
        return placed
    }

    /// Whether an entry's effect carries `keyword`, the `MagicRune` keyword.
    public static func isRune(
        _ payload: SpellPayload, store: MagicEffectStore, keyword: ReferenceKey
    ) -> Bool {
        payload.entries.contains { entry in
            store.resolve(entry.effect, fromPlugin: payload.sourcePlugin)?
                .keywordKeys(in: store).contains(keyword) == true
        }
    }

    /// The nearest of `triggers` inside the rune's proximity, or nil.
    public static func trigger(of rune: PlacedRune, among triggers: [MeleeTarget])
        -> MeleeTarget?
    {
        triggers
            .filter { $0.key != rune.payload.caster }
            .map { (target: $0, distance: SpellHitTargeting.distance(from: rune.position, to: $0)) }
            .filter { $0.distance <= rune.proximity }
            .min { ($0.distance, $0.target.key) < ($1.distance, $1.target.key) }?
            .target
    }
}
