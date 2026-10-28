// The riding numbers and texts that come from game settings. Defaults are the CK wiki's
// Category:Settings values (docs/engine/riding.md).

import Foundation
import OpenSkyGameData

nonisolated public struct MountSettings: Equatable, Sendable {
    /// `iHorseTurnDegreesPerSecond`: how fast a ridden horse turns.
    public var turnDegreesPerSecond: Float = 45
    /// `fMountedMaxLookingDown`: how far, in degrees, a rider may look down.
    public var maximumLookDownDegrees: Float = 40
    /// `sStealHorse`: the question before riding somebody else's horse.
    public var stealQuestion = "Do you want to steal this horse?"
    /// `sNotAllowedToUseAutoDoorsWhileonHorse`: why a rider cannot use a door.
    public var doorRefusal = "Dismount Horse before going through door."
    /// `sRide`: the use-key prompt on a mount.
    public var ride = "Ride"
    /// `sYes` and `sNo`: the buttons of the steal question.
    public var yes = "Yes"
    public var no = "No"
    /// `sTESVDLC2FlyingMountLandingMessage`: the rider ordered a ridden dragon to land.
    /// The vanilla text is localised; this default is OpenSky's.
    public var landingMessage = "Landing."
    /// `sTESVDLC2FlyingMountCancelLandingMessage`: the rider called the landing off.
    public var cancelLandingMessage = "Landing cancelled."
    /// `sTESVDLC2FlyingMountCannotLandMessage`: a script refuses landing requests here.
    public var cannotLandMessage = "You cannot land here."

    public static let vanilla = Self()

    public init() {}

    public var turnRate: Float {
        turnDegreesPerSecond * .pi / 180
    }

    public var maximumLookDown: Float {
        maximumLookDownDegrees * .pi / 180
    }

    public static func resolve(store: GameSettingStore) -> Self {
        resolve(store: store, text: { _ in nil })
    }

    public static func resolve(store: GameSettingStore, text: GameTextResolver) -> Self {
        var settings = vanilla
        if let turn = store.integer("iHorseTurnDegreesPerSecond"), turn > 0 {
            settings.turnDegreesPerSecond = Float(turn)
        }
        if let down = store.number("fMountedMaxLookingDown"), down > 0 {
            settings.maximumLookDownDegrees = down
        }
        store.read("sStealHorse", into: &settings, \.stealQuestion, text: text)
        store.read(
            "sNotAllowedToUseAutoDoorsWhileonHorse", into: &settings, \.doorRefusal, text: text
        )
        store.read("sRide", into: &settings, \.ride, text: text)
        store.read("sYes", into: &settings, \.yes, text: text)
        store.read("sNo", into: &settings, \.no, text: text)
        store.read(
            "sTESVDLC2FlyingMountLandingMessage", into: &settings, \.landingMessage, text: text
        )
        store.read(
            "sTESVDLC2FlyingMountCancelLandingMessage", into: &settings,
            \.cancelLandingMessage, text: text
        )
        store.read(
            "sTESVDLC2FlyingMountCannotLandMessage", into: &settings,
            \.cannotLandMessage, text: text
        )
        return settings
    }
}
