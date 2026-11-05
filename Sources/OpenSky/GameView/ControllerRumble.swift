// Rumbles every connected controller that has haptics, through Apple's Game Controller
// and Core Haptics frameworks. The big motor plays on the left handle and the small one
// on the right, as on a two-motor pad (docs/engine/shouts.md#rumble).

import CoreHaptics
import GameController
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyMagic

final class ControllerRumble {
    var settings = ShoutRumbleSettings.vanilla
    /// The Gameplay page's Vibration switch.
    var isEnabled: () -> Bool = { true }
    /// The last rumble asked for, for the `state player` read.
    private(set) var lastRumble: ShoutRumble?
    /// What asked for the last rumble: `shout`, `weapon`, or `sound`.
    private(set) var lastRumbleCause: String?
    private var engines: [String: CHHapticEngine] = [:]

    func shout(words: Int) {
        guard let rumble = settings.rumble(words: words) else { return }
        play(rumble, cause: "shout")
    }

    /// A weapon's Rumble tab: the left motor is the big one, the right the small one.
    func weapon(_ rumble: Weapon.Rumble) {
        guard rumble.seconds > 0, rumble.left > 0 || rumble.right > 0 else { return }
        play(ShoutRumble(
            bigSeconds: rumble.seconds, bigStrength: rumble.left,
            smallSeconds: rumble.seconds, smallStrength: rumble.right
        ), cause: "weapon")
    }

    func sound(_ rumble: SoundRumble) {
        play(ShoutRumble(
            bigSeconds: rumble.seconds, bigStrength: rumble.big,
            smallSeconds: rumble.seconds, smallStrength: rumble.small
        ), cause: "sound")
    }

    private func play(_ rumble: ShoutRumble, cause: String) {
        guard isEnabled() else { return }
        lastRumble = rumble
        lastRumbleCause = cause
        for controller in GCController.controllers() {
            guard let haptics = controller.haptics else { continue }
            if haptics.supportedLocalities.contains(.leftHandle) {
                play(rumble.bigStrength, rumble.bigSeconds, on: controller, at: .leftHandle)
                play(rumble.smallStrength, rumble.smallSeconds, on: controller, at: .rightHandle)
            } else {
                let strength = max(rumble.bigStrength, rumble.smallStrength)
                let seconds = max(rumble.bigSeconds, rumble.smallSeconds)
                play(strength, seconds, on: controller, at: .default)
            }
        }
    }

    private func play(
        _ strength: Float, _ seconds: Float, on controller: GCController,
        at locality: GCHapticsLocality
    ) {
        guard strength > 0, seconds > 0, let engine = engine(for: controller, at: locality)
        else { return }
        let intensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: min(strength, 1)
        )
        let event = CHHapticEvent(
            eventType: .hapticContinuous, parameters: [intensity], relativeTime: 0,
            duration: TimeInterval(seconds)
        )
        guard
            let pattern = try? CHHapticPattern(events: [event], parameters: []),
            let player = try? engine.makePlayer(with: pattern)
        else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private func engine(for controller: GCController, at locality: GCHapticsLocality)
        -> CHHapticEngine?
    {
        let key = "\(ObjectIdentifier(controller).hashValue)/\(locality.rawValue)"
        if let engine = engines[key] {
            return engine
        }
        guard let engine = controller.haptics?.createEngine(withLocality: locality) else {
            return nil
        }
        engine.isAutoShutdownEnabled = true
        try? engine.start()
        engines[key] = engine
        return engine
    }
}
