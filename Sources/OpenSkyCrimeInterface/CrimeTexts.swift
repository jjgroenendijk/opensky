// The names of crime kinds, from the `sCrimeType*` string settings, and the bounty
// notices from `sAddCrimeGold` and `sRemoveCrimeGold`. The game also
// names pickpocketing and escaping jail, which OpenSky does not count yet. See
// docs/engine/crime.md.

import OpenSkyGameData

nonisolated public struct CrimeTexts: Equatable, Sendable {
    public var names: [CrimeKind: String] = [:]
    public var bountyAdded = "bounty added to"
    public var bountyRemoved = "bounty removed from"
    /// `sWitnessKilled`: the last witness of an open report died.
    public var witnessKilled = "Last witness killed."
    /// The owner's warning. The game speaks it as dialogue; no setting holds a text.
    public var trespassWarning = "You are trespassing. Leave, or you will be reported."

    public static let vanilla = Self()

    public init() {}

    public func name(of kind: CrimeKind) -> String {
        names[kind] ?? kind.rawValue
    }

    /// "40 bounty added to Whiterun"; the word order is OpenSky's reading.
    public func bountyNotice(gold: Int32, added: Bool, faction: String) -> String {
        "\(gold) \(added ? bountyAdded : bountyRemoved) \(faction)"
    }

    static func setting(for kind: CrimeKind) -> String {
        switch kind {
        case .theft: "sCrimeTypeSteal"
        case .assault: "sCrimeTypeAttack"
        case .murder: "sCrimeTypeMurder"
        case .trespass: "sCrimeTypeTrespass"
        case .werewolf: "sCrimeTypeWerewolf"
        }
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        for kind in CrimeKind.allCases {
            if let name = store.text(setting(for: kind)).flatMap({ text($0) }) {
                settings.names[kind] = name
            }
        }
        store.read("sAddCrimeGold", into: &settings, \.bountyAdded, text: text)
        store.read("sRemoveCrimeGold", into: &settings, \.bountyRemoved, text: text)
        store.read("sWitnessKilled", into: &settings, \.witnessKilled, text: text)
        return settings
    }
}
