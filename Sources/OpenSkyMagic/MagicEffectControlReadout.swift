// Active-effect readout lines, formatted in the engine target so a unit test can check
// them without a window. See docs/engine/magic.md.

import Foundation
import OpenSkyMagicInterface

nonisolated public enum MagicEffectControlReadout: Sendable {
    /// What the player's and the nearest actor's effects force on them.
    public static func influenceText(for snapshot: MagicEffectControlSnapshot) -> String {
        guard snapshot.isAvailable else { return "Forced behaviour: unavailable" }
        let player = words(of: snapshot.playerInfluence)
        let nearest = snapshot.nearestActorName.map { name in
            "; \(name): " + words(of: snapshot.nearestActorInfluence)
        } ?? ""
        return "Forced behaviour: player: \(player)\(nearest)"
    }

    /// The influence as words, such as "calmed, paralysed", or "none".
    public static func words(of influence: ActorMagicInfluence) -> String {
        let flags: [(Bool, String)] = [
            (influence.isCalmed, "calmed"), (influence.isFrenzied, "frenzied"),
            (influence.isFrightened, "frightened"), (influence.isRallied, "rallied"),
            (influence.isParalysed, "paralysed"), (influence.isEthereal, "ethereal")
        ]
        let set = flags.filter(\.0).map(\.1)
        return set.isEmpty ? "none" : set.joined(separator: ", ")
    }
}
