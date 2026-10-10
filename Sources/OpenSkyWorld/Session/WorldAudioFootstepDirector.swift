// Routes the bridge's graph events to footstep audio. No step timer: vanilla clips carry
// `FootLeft` and `FootRight` events at the frame a foot lands, and a speed cadence would
// drift from the animation. Driven by the per-frame audio tick, skipped while paused.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

@MainActor
public final class WorldAudioFootstepDirector {
    public static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldAudioFootstep"
    )

    private let engine: WorldAudioEngine
    private let footstepStore: FootstepStore?
    private let soundStore: SoundRecordStore?
    private let assets: AudioAssetLoader
    /// MATT index, for naming the ground material in the readout. Empty in a
    /// synthetic session, and then a material is reported by FormID.
    public var materialTypes = MaterialTypeIndex.empty

    /// Footstep playback. On by default, like the SFX and ambience beds; the
    /// World > Audio panel writes back here.
    /// Each routed step's impact, for its dust model; set by the session.
    public var onImpact: ((Impact, SIMD3<Float>) -> Void)?
    public var footstepsEnabled = true

    /// The MATT under the player's feet in the last routed frame. Nil while airborne.
    public private(set) var groundMaterial: FormID?

    /// A material the panel pins in place of the ground contact's, for
    /// verifying that a chosen surface really does select a different sound.
    /// Nil — the default — follows the ground.
    public var forcedMaterial: FormID?

    /// The set the player currently walks with. Starts at the store's default
    /// set and is replaced when the player's feet armature resolves to one.
    public private(set) var footstepSet: FootstepSet?

    /// Last resolved footstep, for the panel readout.
    public private(set) var lastFootstepDescription: String?
    public private(set) var lastFootstepError: String?
    /// Events routed and events played since construction. The two differ by
    /// the tags the current set has no footstep for, which is normal vanilla
    /// data rather than a fault, so both are reported.
    public private(set) var routedEventCount = 0
    public private(set) var playedFootstepCount = 0

    public init(
        engine: WorldAudioEngine,
        footstepStore: FootstepStore?,
        soundStore: SoundRecordStore?,
        assets: AudioAssetLoader
    ) {
        self.engine = engine
        self.footstepStore = footstepStore
        self.soundStore = soundStore
        self.assets = assets
        footstepSet = footstepStore?.defaultSet
    }

    /// Test seam: same shape, with the file loader injected directly.
    public init(
        engine: WorldAudioEngine,
        footstepStore: FootstepStore?,
        soundStore: SoundRecordStore?,
        fileLoader: @escaping (String) throws -> Data
    ) {
        self.engine = engine
        self.footstepStore = footstepStore
        self.soundStore = soundStore
        assets = AudioAssetLoader(immediate: fileLoader)
        footstepSet = footstepStore?.defaultSet
    }

    /// Picks the footstep set from the armatures on the player's feet, falling
    /// back to the store's default. Called when the player body is assembled or
    /// re-equipped; passing an empty list restores the default.
    public func updateFootstepSet(feetArmatures: [FormID]) {
        footstepSet = footstepStore?.set(forArmatures: feetArmatures)
    }

    /// Routes one frame's graph events. Events with no tag in the gait's footstep list are
    /// dropped. Steps play at the player's feet with the ground contact's MATT, so snow and
    /// wood sound different.
    public func handleGraphEvents(
        _ names: [String],
        gait: LocomotionGait,
        position: SIMD3<Float>,
        material: FormID? = nil
    ) {
        groundMaterial = material
        guard footstepsEnabled, engine.isRunning, !names.isEmpty else { return }
        guard let footstepStore, let footstepSet else { return }
        for name in names {
            guard
                let resolved = footstepStore.resolve(
                    tag: name,
                    gait: Self.footstepGait(for: gait),
                    in: footstepSet,
                    material: activeMaterial
                )
            else { continue }
            routedEventCount += 1
            onImpact?(resolved.impact, position)
            play(resolved, tag: name, at: position)
        }
    }

    /// Which of the FSTS lists a locomotion gait reads. One-to-one: the five
    /// gaits the bridge resolves are the five lists a footstep set carries.
    nonisolated public static func footstepGait(for gait: LocomotionGait) -> FootstepGait {
        switch gait {
        case .walk: .walking
        case .run: .running
        case .sprint: .sprinting
        case .sneak: .sneaking
        case .swim: .swimming
        }
    }

    /// The tags the current set answers to for one gait, for the readout.
    public func tags(for gait: LocomotionGait) -> [String] {
        guard let footstepStore, let footstepSet else { return [] }
        return footstepStore.tags(for: Self.footstepGait(for: gait), in: footstepSet)
    }

    /// Plays one footstep for `tag` without waiting for the graph to fire it.
    /// The World > Audio panel's verification control; returns nil on success
    /// or a short reason for the readout.
    public func forcePlayFootstep(
        tag: String,
        gait: LocomotionGait,
        position: SIMD3<Float>
    ) -> String? {
        guard engine.isRunning else { return "engine not running" }
        guard let footstepStore, let footstepSet else { return "no footstep records" }
        guard
            let resolved = footstepStore.resolve(
                tag: tag,
                gait: Self.footstepGait(for: gait),
                in: footstepSet,
                material: activeMaterial
            )
        else { return "\(tag) resolves to no sound in \(describe(footstepSet))" }
        routedEventCount += 1
        onImpact?(resolved.impact, position)
        return play(resolved, tag: tag, at: position)
    }

    /// The material every resolution is made against: the panel's pinned one
    /// when it has pinned one, else the ground contact's.
    public var activeMaterial: FormID? {
        forcedMaterial ?? groundMaterial
    }

    /// How the panel names the current set.
    public var footstepSetDescription: String {
        guard let footstepSet else { return "none" }
        return describe(footstepSet)
    }

    /// How the panel names the surface footsteps currently resolve against.
    public var materialDescription: String {
        guard let material = activeMaterial else { return "none" }
        let name = materialTypes.describe(material)
        return forcedMaterial == nil ? name : "\(name) (forced)"
    }

    /// Every material the panel can pin, ordered by name so the menu is stable.
    public var selectableMaterials: [(id: FormID, name: String)] {
        materialTypes.materials.values
            .map { (id: $0.formID, name: materialTypes.describe($0.formID)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func describe(_ set: FootstepSet) -> String {
        set.editorID ?? set.formID.description
    }

    /// Nil when the step played or waits for its file; else the reason it did not.
    @discardableResult
    private func play(
        _ resolved: ResolvedFootstep,
        tag: String,
        at position: SIMD3<Float>
    ) -> String? {
        guard let soundStore else {
            lastFootstepError = "no sound records"
            return lastFootstepError
        }
        guard
            let sound = try? soundStore.resolveAny(resolved.sound),
            let path = sound.filePaths.first
        else {
            lastFootstepError = "unresolved \(tag) -> \(resolved.sound.description)"
            return lastFootstepError
        }
        // The SNCT chain places vanilla footstep descriptors under
        // `AudioCategoryFST`; the fallback is for a chain that reaches no menu category.
        let request = AudioPlayRequest(
            name: path, category: sound.audioCategory ?? .footsteps, worldPosition: position
        )
        var reason: String?
        assets.request(path) { [weak self] result in
            reason = self?.start(result, request: request, tag: tag)
        }
        return reason
    }

    private func start(
        _ result: Result<AudioFileAsset, AssetLoadFailure>,
        request: AudioPlayRequest,
        tag: String
    ) -> String? {
        do {
            try engine.playPositional(asset: result.get(), request: request)
            playedFootstepCount += 1
            lastFootstepDescription = "\(tag): \(request.name)"
            lastFootstepError = nil
            return nil
        } catch {
            let reason = String(describing: error)
            lastFootstepError = reason
            Self.logger.warning(
                "[WARNING] footstep play failed: \(reason, privacy: .public)"
            )
            return reason
        }
    }
}
