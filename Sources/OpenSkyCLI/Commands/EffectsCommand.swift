// `effects census` prints the load-order effect records the effect runtimes read:
// IMAD timing, IMGS grading ranges, SPGD precipitation, SOPM output models, and
// REVB reverbs. `effects imad <edid> [--at <seconds>]` samples one modifier.
// See docs/formats/image-spaces.md and docs/formats/sound-output-reverb.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

enum EffectsCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let mode = try scanner.positional("census or imad")
        let editorID = mode == "imad" ? try scanner.positional("IMAD editor ID") : nil
        let time = try scanner.option("--at").flatMap(Float.init) ?? 0
        try scanner.finish()
        let file = try context.loadSkyrimESM()
        let store = EffectRecordStore(plugins: ActivePluginFiles.load(
            root: context.root,
            baseFile: file
        ))
        switch mode {
        case "census":
            printAdapters(store)
            printImageSpaces(store)
            printParticles(store)
            printAudio(store)
            printExplosions(store)
        case "imad":
            guard let editorID, let adapter = store.imageSpaceAdapters.record(editorID: editorID)
            else { throw CLIError.failure("no IMAD \(editorID ?? "")") }
            printSample(adapter.record, at: time)
        default:
            throw CLIError.usage("effects takes census or imad")
        }
    }

    private static func printAdapters(_ store: EffectRecordStore) {
        let adapters = store.imageSpaceAdapters.records.map(\.record)
        let animatable = adapters.count { $0.header?.isAnimatable == true }
        var pastDuration = 0
        var normalized = 0
        for adapter in adapters {
            let duration = adapter.header?.duration ?? 0
            let times = adapter.envelopes.values.flatMap { $0.map(\.time) }
                + adapter.tint.map(\.time) + adapter.fade.map(\.time)
            let last = times.max() ?? 0
            if last > duration * 1.01 + 0.001 {
                pastDuration += 1
            }
            if duration > 1.5, last > 0, last <= 1.0 {
                normalized += 1
            }
            print(
                "IMAD \(adapter.editorID ?? "?") duration \(duration) last key \(last) "
                    + "animatable \(adapter.header?.isAnimatable == true)"
            )
        }
        let durations = adapters.compactMap { $0.header?.duration }
        print("IMAD \(adapters.count): animatable \(animatable)")
        print("IMAD duration: \(range(durations))")
        print(
            "IMAD keys past duration: \(pastDuration), "
                + "keys within 0-1 of a longer duration: \(normalized)"
        )
        let channels = adapters.flatMap { Array($0.envelopes.keys) }
        let counts = Dictionary(grouping: channels.map { "\($0)" }, by: { $0 }).mapValues(\.count)
        for (channel, count) in counts.sorted(by: { $0.key < $1.key }) {
            print("IMAD channel \(channel): \(count)")
        }
        print(
            "IMAD tint: \(adapters.count { !$0.tint.isEmpty }), "
                + "fade: \(adapters.count { !$0.fade.isEmpty })"
        )
    }

    private static func printImageSpaces(_ store: EffectRecordStore) {
        let spaces = store.imageSpaces.records.map(\.record)
        print("IMGS \(spaces.count)")
        print("IMGS saturation: \(range(spaces.compactMap { $0.cinematic?.saturation }))")
        print("IMGS brightness: \(range(spaces.compactMap { $0.cinematic?.brightness }))")
        print("IMGS contrast: \(range(spaces.compactMap { $0.cinematic?.contrast }))")
        print("IMGS tint amount: \(range(spaces.compactMap { $0.tint?.amount }))")
        let tinted = spaces.filter { ($0.tint?.amount ?? 0) >= 0.9 }.compactMap(\.editorID).sorted()
        print("IMGS strong tint: \(tinted.prefix(12).joined(separator: ", "))")
    }

    private static func printParticles(_ store: EffectRecordStore) {
        for record in store.shaderParticles.records {
            guard let data = record.record.properties else { continue }
            print(
                "SPGD \(record.record.editorID ?? "?") type \(data.type) "
                    + "gravity \(data.gravityVelocity) rotation \(data.rotationVelocity) "
                    + "size \(data.particleSize.x)x\(data.particleSize.y) "
                    + "offset \(data.centerOffsetMinimum)-\(data.centerOffsetMaximum) "
                    + "box \(data.boxSize.map(String.init) ?? "-") "
                    + "density \(data.particleDensity.map { "\($0)" } ?? "-")"
            )
        }
    }

    private static func printAudio(_ store: EffectRecordStore) {
        for record in store.outputModels.records {
            let model = record.record
            let curve = model.attenuation.map {
                "\($0.minimumDistance)-\($0.maximumDistance) \($0.curve)"
            } ?? "-"
            print(
                "SOPM \(model.editorID ?? "?") type \(model.type.map(String.init) ?? "-") "
                    + "flags \(model.flags.map(String.init) ?? "-") "
                    + "reverb \(model.reverbSendPercent.map(String.init) ?? "-") "
                    + "attenuation \(curve)"
            )
        }
        for record in store.reverbs.records {
            guard let data = record.record.properties else { continue }
            print(
                "REVB \(record.record.editorID ?? "?") decay \(data.decayTimeMilliseconds)ms "
                    + "room \(data.roomFilter) roomHF \(data.roomHFFilter) "
                    + "reflections \(data.reflections) "
                    + "reverb \(data.reverbAmplitude) hfRatio \(data.decayHFRatio) "
                    + "delay \(data.reflectDelay)/\(data.reverbDelayMilliseconds) "
                    + "diffusion \(data.diffusionPercent) density \(data.densityPercent)"
            )
        }
    }

    private static func printExplosions(_ store: EffectRecordStore) {
        var placed: [String: Int] = [:]
        var withDamage = 0
        var withModifier = 0
        for record in store.explosions.records {
            let explosion = record.record
            if (explosion.properties?.damage ?? 0) > 0 {
                withDamage += 1
            }
            if explosion.imageSpaceModifier != nil {
                withModifier += 1
            }
            guard
                let link = store.explosions.link(explosion.properties?.placedObject, from: record)
            else { continue }
            let type = switch store.explosions.index.lookup(link.target) {
            case let .record(indexed): "\(indexed.record.type)"
            default: "other"
            }
            placed[type, default: 0] += 1
        }
        print(
            "EXPL \(store.explosions.records.count): damage \(withDamage), "
                + "image space \(withModifier)"
        )
        print("EXPL placed objects: \(placed.sorted { $0.key < $1.key })")
    }

    private static func printSample(_ adapter: ImageSpaceAdapter, at time: Float) {
        let sample = adapter.sample(elapsed: time)
        print(
            "IMAD \(adapter.editorID ?? "?") duration \(adapter.playbackDuration) at \(sample.time)"
        )
        for (channel, value) in sample.values.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            let keys = adapter.envelopes[channel] ?? []
            print(
                "  \(channel) = \(value) from \(keys.map { "(\($0.time), \($0.value))" }.joined())"
            )
        }
        print(
            "  tint = \(sample.tint.map { "\($0)" } ?? "-"), "
                + "fade = \(sample.fade.map { "\($0)" } ?? "-")"
        )
    }

    private static func range(_ values: [Float]) -> String {
        guard let low = values.min(), let high = values.max() else { return "none" }
        let mean = values.reduce(0, +) / Float(values.count)
        return "\(low) to \(high), mean \(mean), n \(values.count)"
    }
}
