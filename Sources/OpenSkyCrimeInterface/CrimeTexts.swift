// The names of crime kinds, from the `sCrimeType*` string settings. The game also
// names pickpocketing, escaping jail, and werewolf transformation, which OpenSky
// does not count yet. See docs/engine/crime.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct CrimeTexts: Equatable, Sendable {
    public var names: [CrimeKind: String] = [:]

    public static let vanilla = Self()

    public init() {}

    public func name(of kind: CrimeKind) -> String {
        names[kind] ?? kind.rawValue
    }

    static func setting(for kind: CrimeKind) -> String {
        switch kind {
        case .theft: "sCrimeTypeSteal"
        case .assault: "sCrimeTypeAttack"
        case .murder: "sCrimeTypeMurder"
        case .trespass: "sCrimeTypeTrespass"
        }
    }

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var settings = vanilla
        for kind in CrimeKind.allCases {
            if let name = store.text(setting(for: kind)).flatMap({ text($0.text) }) {
                settings.names[kind] = name
            }
        }
        return settings
    }
}
