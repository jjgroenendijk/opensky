// World SFX + ambience director (M9.2.2, issue #155). Subscribes to the
// streamer's interaction + ambience-context callbacks and drives the audio
// engine accordingly:
//
//   - One-shot SFX (door open, activator activate) on use-key events, under
//     the `effects` category, fired from the placed reference's position.
//   - Continuous ambience loop set when the center cell changes, under the
//     `ambience` category, fired from the listener position (a stopgap until
//     a non-positional bed path exists; see issue #236).
//
// Main-actor only (the engine + streamer are main-actor); decode work runs
// inside WorldAudioEngine's decode queue. Defensive: an absent engine, store,
// or file-system entry degrades silently — no audio, no crash. The director
// is the single consumer of the CellStreamer.onInteraction seam the M8 work
// reserved for "the later Papyrus OnActivate subscriber"; that Papyrus
// subscriber will subscribe alongside, not replace this one.

import Foundation
import OSLog
import simd

@MainActor
final class WorldAudioSoundDirector {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldAudioDirector"
    )

    private let engine: WorldAudioEngine
    private let soundStore: SoundRecordStore?
    private let weatherStore: WeatherStore?
    private let aspcStore: AcousticSpaceStore?
    /// Resolves a canonical sound-path string to its file bytes. Production
    /// wraps `VirtualFileSystem.contents(forPath:)`; tests inject a stub.
    private let fileLoader: (String) throws -> Data

    /// SFX on use-key activation. Off by default until the user enables audio;
    /// the panel control writes back here.
    var sfxEnabled = true
    /// Continuous ambience bed. Same default policy as `sfxEnabled`.
    var ambienceEnabled = true

    /// Active ambience source ids owned by this director. Tracked so a context
    /// change can retire exactly the previous bed without touching unrelated
    /// one-shot SFX the engine is also playing.
    private var ambienceSourceIDs: [Int] = []
    /// Last resolved bed; diffed against a fresh context to skip no-op restarts.
    private var currentBed = AmbienceBed.empty

    /// Most recent SFX outcome, surfaced through the World > Audio readout.
    private(set) var lastSFXDescription: String?
    private(set) var lastSFXError: String?

    init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        fileSystem: VirtualFileSystem?
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        fileLoader = { path in
            guard let fileSystem else {
                throw NSError(domain: "WorldAudioSoundDirector", code: 1)
            }
            return try fileSystem.contents(forPath: path)
        }
    }

    /// Test seam: same shape as the production init but takes a file loader
    /// closure directly so tests do not need a real VirtualFileSystem.
    init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        fileLoader: @escaping (String) throws -> Data
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        self.fileLoader = fileLoader
    }

    // MARK: - Streamer event hooks

    /// CellStreamer.onInteraction subscriber. Plays the activator's activation
    /// sound (DOOR.SNAM, ACTI.VNAM, CONT.SNAM) at the placed position. Close
    /// and loop sounds ride along on PlacedInteraction but wait on door-
    /// animation wiring (issue #234).
    func handleInteraction(_ event: InteractionEvent) {
        guard sfxEnabled, engine.isRunning else { return }
        guard
            let sounds = event.target.interaction.sounds,
            let activationID = sounds.activation
        else { return }
        playResolved(
            id: activationID,
            at: event.target.interaction.position,
            category: .effects,
            kind: "SFX"
        )
    }

    /// CellStreamer.onAmbienceContextChanged subscriber. Resolves the new bed
    /// and, when it differs from the active one, retires the previous sources
    /// and starts the new ones. No-op when ambience is disabled, the engine is
    /// not running, or the bed did not change.
    func handleAmbienceContext(_ context: AmbienceContext) {
        let bed = AmbienceBed.resolve(
            context: context,
            weatherStore: weatherStore,
            aspcStore: aspcStore
        )
        guard bed != currentBed else { return }
        currentBed = bed
        retireAmbience()
        guard ambienceEnabled, engine.isRunning else { return }
        startAmbience(bed: bed)
    }

    // MARK: - Panel entry points (Phase 3 verification surface)

    /// Forces a one-shot SFX for any resolved SNDR FormID. Used by the World >
    /// Audio panel to verify SFX without relying on a walk-mode interaction.
    func forcePlaySound(formID: FormID, position: SIMD3<Float>) {
        guard engine.isRunning else {
            lastSFXError = "engine not running"
            return
        }
        playResolved(
            id: formID, at: position, category: .effects, kind: "SFX"
        )
    }

    /// Last ambience bed the director resolved, for the panel readout.
    var currentAmbienceDescription: String {
        guard !currentBed.entries.isEmpty else { return "none" }
        return currentBed.entries
            .map(\.sound.description)
            .joined(separator: ", ")
    }

    // MARK: - Internals

    private func playResolved(
        id: FormID,
        at position: SIMD3<Float>,
        category: AudioCategory,
        kind: String
    ) {
        guard let resolved = resolveSound(id: id) else {
            lastSFXError = "unresolved \(id.description)"
            Self.logger.debug(
                "[INFO] \(kind, privacy: .public) unresolved: \(id.description, privacy: .public)"
            )
            return
        }
        do {
            try engine.playPositional(
                fileData: resolved.data,
                request: AudioPlayRequest(
                    name: resolved.name, category: category, worldPosition: position
                )
            )
            lastSFXDescription = resolved.name
            lastSFXError = nil
        } catch {
            let reason = String(describing: error)
            lastSFXError = reason
            Self.logger.warning(
                "[WARNING] \(kind, privacy: .public) play failed: \(reason, privacy: .public)"
            )
        }
    }

    private func startAmbience(bed: AmbienceBed) {
        // Stopgap: ambience plays positional at the listener. A future
        // non-positional bed path (issue #236) replaces this.
        let position = engine.listenerWorldPosition
        for entry in bed.entries {
            guard let resolved = resolveSound(id: entry.sound) else { continue }
            do {
                try engine.playPositional(
                    fileData: resolved.data,
                    request: AudioPlayRequest(
                        name: resolved.name,
                        category: .ambience,
                        worldPosition: position,
                        gain: ambienceGainPerEntry(in: bed)
                    )
                )
                if let id = engine.sources.last?.id {
                    ambienceSourceIDs.append(id)
                }
            } catch {
                let reason = String(describing: error)
                Self.logger.warning(
                    "[WARNING] ambience start failed: \(reason, privacy: .public)"
                )
            }
        }
    }

    /// Splits unity across the bed entries so N concurrent loops do not sum to
    /// N x master. Equal-weight today; the RDSA.Chance field (issue pending
    /// probe) will refine this.
    private func ambienceGainPerEntry(in bed: AmbienceBed) -> Float {
        bed.entries.isEmpty ? 1 : 1 / Float(bed.entries.count)
    }

    private func retireAmbience() {
        for id in ambienceSourceIDs {
            engine.stopSource(id: id)
        }
        ambienceSourceIDs.removeAll()
    }

    private func resolveSound(id: FormID) -> (data: Data, name: String)? {
        guard let soundStore else { return nil }
        let resolved: ResolvedSound
        do {
            resolved = try soundStore.resolveAny(id)
        } catch {
            return nil
        }
        guard let path = resolved.filePaths.first else { return nil }
        guard let data = try? fileLoader(path) else { return nil }
        return (data, path)
    }
}
