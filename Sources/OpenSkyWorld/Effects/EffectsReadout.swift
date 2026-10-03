// The text of the image-space and visual-effect readouts, kept out of the
// panels so a unit test can pin it.

import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering

nonisolated public enum EffectsReadout {
    /// Rows shown per list; the rest are counted.
    public static let listedRows = 6

    public static func imageSpace(_ state: ImageSpaceState) -> String {
        let baseline = state.forcedBaseline.map { "\($0.record.editorID ?? "forced") (forced)" }
            ?? state.baseline.dominantName
        let sources = state.baseline.sources
            .map { "\($0.name) \(Int(($0.weight * 100).rounded()))%" }
            .joined(separator: ", ")
        let values = state.current
        var lines = [
            "Baseline: \(baseline)",
            "Sources: \(sources.isEmpty ? "none" : sources)",
            "Saturation \(number(values.saturation)) · brightness \(number(values.brightness))"
                + " · contrast \(number(values.contrast))",
            "Tint: \(number(values.tint.x)) \(number(values.tint.y)) \(number(values.tint.z))"
                + " at \(number(values.tint.w))",
            "Modifiers: \(state.modifiers.instances.count)"
        ]
        lines += state.modifiers.instances.prefix(listedRows).map { instance in
            let left = instance.remaining.map { "\(number($0)) s left" } ?? "looping"
            return "  \(instance.name) × \(number(instance.strength)), \(left)"
        }
        if !state.passEnabled {
            lines.append("Pass: off")
        }
        return lines.joined(separator: "\n")
    }

    public static func visualEffects(_ snapshot: VisualEffectSnapshot) -> String {
        var lines = [
            "Effects: \(snapshot.instances.count) live · \(snapshot.attachedTotal) attached"
                + " · \(snapshot.failedModels) bad models",
            "Spell hit: \(snapshot.lastSpellHit)"
        ]
        lines += snapshot.instances.prefix(listedRows).map(line)
        if snapshot.instances.count > listedRows {
            lines.append("  and \(snapshot.instances.count - listedRows) more")
        }
        return lines.joined(separator: "\n")
    }

    static func line(_ instance: VisualEffectInstance) -> String {
        let anchor = switch instance.anchor {
        case let .actor(key): key == .player ? "player" : key.description
        case .point: "a point"
        }
        let left = instance.duration.map { "\(number(max(0, $0 - instance.elapsed))) s left" }
            ?? "lasting"
        return "  \(instance.spec.name) on \(anchor), \(left)"
    }

    private static func number(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}
