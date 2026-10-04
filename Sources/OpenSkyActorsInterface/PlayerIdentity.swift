// The player's chosen race, sex, name, and face. It starts as the vanilla `Player`
// record (NPC_ 00000007) and the race menu changes it. Kept on the player's delta,
// so the save carries it. See docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One painted tint layer: a race tint mask, its color, and how strong it is.
nonisolated public struct PlayerTintLayer: Equatable, Sendable {
    /// TINI, the mask index in the race's tint list.
    public var maskIndex: UInt16
    public var color: SIMD4<UInt8>
    /// 0 to 1; the record's TINV percent divided by 100.
    public var strength: Float

    public init(maskIndex: UInt16, color: SIMD4<UInt8>, strength: Float) {
        self.maskIndex = maskIndex
        self.color = color
        self.strength = strength
    }
}

/// The face values NPC_ records carry, which the race menu edits.
nonisolated public struct PlayerFace: Equatable, Sendable {
    /// NAM9: the 19 slider values, nose long or short first.
    public var morphs: [Float]
    /// NAMA: the nose, unknown, eyes, and mouth morph group options.
    public var parts: [Int32]
    /// PNAM head parts chosen over the race defaults: hair, eyes, brows, beard, scars.
    public var headParts: [FormID]
    public var hairColor: FormID?
    public var tints: [PlayerTintLayer]
    /// NAM7, 0 to 100: blends the `_0` and `_1` meshes.
    public var weight: Float
    /// NAM6, a scale; 1 is the race height.
    public var height: Float

    public init(
        morphs: [Float] = [], parts: [Int32] = [], headParts: [FormID] = [],
        hairColor: FormID? = nil, tints: [PlayerTintLayer] = [], weight: Float = 50,
        height: Float = 1
    ) {
        self.morphs = morphs
        self.parts = parts
        self.headParts = headParts
        self.hairColor = hairColor
        self.tints = tints
        self.weight = weight
        self.height = height
    }
}

nonisolated public struct PlayerIdentityState: WorldStateComponent, Sendable {
    public static let nameLimit = 64

    public var race: FormID
    public var isFemale: Bool
    public var name: String
    public var face: PlayerFace

    public static var componentKind: WorldStateComponentKind {
        .playerIdentity
    }

    public init(race: FormID, isFemale: Bool, name: String, face: PlayerFace = PlayerFace()) {
        self.race = race
        self.isFemale = isFemale
        self.name = String(name.prefix(Self.nameLimit))
        self.face = face
    }

    /// The vanilla `Player` record as an identity, before the race menu.
    public init(record: ActorBase, details: ActorBaseDetails?, name: String) {
        let face = details.map { details in
            PlayerFace(
                morphs: details.faceMorphs, parts: details.faceParts,
                headParts: record.headParts, hairColor: details.hairColor,
                tints: details.tintLayers.compactMap(Self.tint), weight: details.weight ?? 50,
                height: details.height ?? 1
            )
        } ?? PlayerFace(headParts: record.headParts)
        self.init(
            race: record.race ?? FormID(0), isFemale: record.isFemale, name: name, face: face
        )
    }

    private static func tint(_ layer: ActorTintLayer) -> PlayerTintLayer? {
        guard let index = layer.index, let color = layer.color else { return nil }
        return PlayerTintLayer(
            maskIndex: index, color: color,
            strength: Float(layer.interpolation ?? 100) / 100
        )
    }
}

nonisolated extension WorldStateComponentKind {
    /// The player's race, sex, name, and face. Keyed by the player.
    public static let playerIdentity = Self(
        rawValue: "playerIdentity", order: 26, affectsCellBuild: false
    )
}
