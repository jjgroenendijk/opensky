// Footstep director (issue #352): the seam between the locomotion bridge's
// fired graph events and the M9 audio engine.
//
// There is no step timer here, and there must not be one. The vanilla
// locomotion clips carry their own footstep triggers — `0_master.hkx` declares
// `FootLeft` and `FootRight` as its first two of 1,217 events — so the graph
// already says when a foot lands, at the phase the animation actually plants
// it. Inventing a cadence from speed would drift against the animation the
// player is watching. This type therefore only listens.
//
// Main-actor only, like the other two directors; it is driven from the
// renderer's per-frame audio tick, which already runs on the main thread and
// is skipped entirely while the world sim is paused.

import Foundation
import OSLog
import simd

@MainActor
final class WorldAudioFootstepDirector {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldAudioFootstep"
    )

    private let engine: WorldAudioEngine
    private let footstepStore: FootstepStore?
    private let soundStore: SoundRecordStore?
    private let fileLoader: (String) throws -> Data
    /// MATT index, for naming the ground material in the readout. Empty in a
    /// synthetic session, and then a material is reported by FormID.
    var materialTypes = MaterialTypeIndex.empty

    /// Footstep playback. On by default, like the SFX and ambience beds; the
    /// World > Audio panel writes back here.
    var footstepsEnabled = true

    /// The MATT the last routed frame reported under the player's feet
    /// (issue #358), nil while airborne or on a surface that names none.
    private(set) var groundMaterial: FormID?

    /// A material the panel pins in place of the ground contact's, for
    /// verifying that a chosen surface really does select a different sound.
    /// Nil — the default — follows the ground.
    var forcedMaterial: FormID?

    /// The set the player currently walks with. Starts at the store's default
    /// set and is replaced when the player's feet armature resolves to one.
    private(set) var footstepSet: FootstepSet?

    /// Last resolved footstep, for the panel readout.
    private(set) var lastFootstepDescription: String?
    private(set) var lastFootstepError: String?
    /// Events routed and events played since construction. The two differ by
    /// the tags the current set has no footstep for, which is normal vanilla
    /// data rather than a fault, so both are reported.
    private(set) var routedEventCount = 0
    private(set) var playedFootstepCount = 0

    init(
        engine: WorldAudioEngine,
        footstepStore: FootstepStore?,
        soundStore: SoundRecordStore?,
        fileSystem: VirtualFileSystem?
    ) {
        self.engine = engine
        self.footstepStore = footstepStore
        self.soundStore = soundStore
        fileLoader = { path in
            guard let fileSystem else {
                throw NSError(domain: "WorldAudioFootstepDirector", code: 1)
            }
            return try fileSystem.contents(forPath: path)
        }
        footstepSet = footstepStore?.defaultSet
    }

    /// Test seam: same shape, with the file loader injected directly.
    init(
        engine: WorldAudioEngine,
        footstepStore: FootstepStore?,
        soundStore: SoundRecordStore?,
        fileLoader: @escaping (String) throws -> Data
    ) {
        self.engine = engine
        self.footstepStore = footstepStore
        self.soundStore = soundStore
        self.fileLoader = fileLoader
        footstepSet = footstepStore?.defaultSet
    }

    /// Picks the footstep set from the armatures on the player's feet, falling
    /// back to the store's default. Called when the player body is assembled or
    /// re-equipped; passing an empty list restores the default.
    func updateFootstepSet(feetArmatures: [FormID]) {
        footstepSet = footstepStore?.set(forArmatures: feetArmatures)
    }

    /// Routes one frame's worth of drained graph events.
    ///
    /// Every event is offered to the current gait's footstep list; the ones the
    /// list has no tag for — the graph fires plenty, from combat to magic — are
    /// dropped without a lookup past the tag comparison. `position` is the
    /// player's feet, so the step is heard where it is made rather than at the
    /// listener, and `material` is the MATT the ground contact reported there,
    /// which is what makes snow and wood sound different (issue #358).
    func handleGraphEvents(
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
            play(resolved, tag: name, at: position)
        }
    }

    /// Which of the FSTS lists a locomotion gait reads. One-to-one: the five
    /// gaits the bridge resolves are the five lists a footstep set carries.
    nonisolated static func footstepGait(for gait: LocomotionGait) -> FootstepGait {
        switch gait {
        case .walk: .walking
        case .run: .running
        case .sprint: .sprinting
        case .sneak: .sneaking
        case .swim: .swimming
        }
    }

    /// The tags the current set answers to for one gait, for the readout.
    func tags(for gait: LocomotionGait) -> [String] {
        guard let footstepStore, let footstepSet else { return [] }
        return footstepStore.tags(for: Self.footstepGait(for: gait), in: footstepSet)
    }

    /// Plays one footstep for `tag` without waiting for the graph to fire it.
    /// The World > Audio panel's verification control; returns nil on success
    /// or a short reason for the readout.
    func forcePlayFootstep(
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
        return play(resolved, tag: tag, at: position)
    }

    /// The material every resolution is made against: the panel's pinned one
    /// when it has pinned one, else the ground contact's.
    var activeMaterial: FormID? {
        forcedMaterial ?? groundMaterial
    }

    /// How the panel names the current set.
    var footstepSetDescription: String {
        guard let footstepSet else { return "none" }
        return describe(footstepSet)
    }

    /// How the panel names the surface footsteps currently resolve against.
    var materialDescription: String {
        guard let material = activeMaterial else { return "none" }
        let name = materialTypes.describe(material)
        return forcedMaterial == nil ? name : "\(name) (forced)"
    }

    /// Every material the panel can pin, ordered by name so the menu is stable.
    var selectableMaterials: [(id: FormID, name: String)] {
        materialTypes.materials.values
            .map { (id: $0.formID, name: materialTypes.describe($0.formID)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func describe(_ set: FootstepSet) -> String {
        set.editorID ?? set.formID.description
    }

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
            let path = sound.filePaths.first,
            let data = try? fileLoader(path)
        else {
            lastFootstepError = "unresolved \(tag) -> \(resolved.sound.description)"
            return lastFootstepError
        }
        do {
            try engine.playPositional(
                fileData: data,
                request: AudioPlayRequest(
                    name: path,
                    // The SNCT chain places vanilla footstep descriptors under
                    // `AudioCategoryFST` on its own; the fallback only matters
                    // for a descriptor whose chain does not reach a menu
                    // category, and footsteps is the right home for it.
                    category: sound.audioCategory ?? .footsteps,
                    worldPosition: position
                )
            )
            playedFootstepCount += 1
            lastFootstepDescription = "\(tag): \(path)"
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
