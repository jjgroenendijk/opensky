// The perk sky behind the skills menu: the dome, every tree's stars and lines, and
// the camera, rebuilt each frame as a menu scene. The world stays hidden under an
// empty loading cover. See docs/engine/perk-sky.md.

import Foundation
import OpenSkyFormatsMesh
import OpenSkyProgressionInterface
import OpenSkyRendering
import simd

nonisolated struct PerkStarKey: Hashable, Sendable {
    let skill: Int32
    let node: UInt32
}

nonisolated struct PerkLineKey: Hashable, Sendable {
    let skill: Int32
    let parent: UInt32
    let child: UInt32
}

/// What one frame of the sky draws with.
struct PerkSkyFrame {
    let models: PerkSkySource.Models
    let settings: PerkSkySettings
    let now: Double
    let camera: PerkSkyCamera
    /// The line mesh's length to `BeamEnd`.
    let beamLength: Float
}

/// The stars and lines of every tree, and the open tree's stars for the names.
struct PerkSkyTreeDraws {
    var stars: [MenuSceneDraw] = []
    var lines: [MenuSceneDraw] = []
    var openTree: [PerkSkyStar] = []
}

/// What the sky keeps between frames while the menu is open.
struct PerkSkyState {
    var trees: [Int32: [SkillsMenuPerk]] = [:]
    var motion: PerkSkyMotion?
    var stars = PerkSkyAnimator<PerkStarKey>()
    var lines = PerkSkyAnimator<PerkLineKey>()
    var anchors: [SIMD3<Float>] = []
    var openedAt: Double?
    var lastTick: Double?
    var movieAlpha: Float?
    var namePoints: [UInt32: SIMD2<Float>] = [:]
    var isShown = false
    var drawCount = 0
}

extension SkillsMenuCoordinator {
    static let soundKeyPrefix = "SoundPlay."
    /// Name moves smaller than this, in stage fractions, are not sent to the movie.
    static let nameTolerance: Float = 0.001

    func loadTrees(_ source: any SkillsMenuSource) {
        sky.trees = Dictionary(
            source.skillsMenuSkills.map { ($0.index, source.skillsMenuPerks(forSkill: $0.index)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The sky readout line; nil before the sky first shows.
    var skyLine: String? {
        if let failure = world?.perkSkySource?.failure {
            return "failed: \(failure)"
        }
        guard sky.isShown, let motion = sky.motion else { return nil }
        let view = motion.treeBlend >= 1 ? "tree view" : motion.treeBlend > 0 ? "moving" : "ring"
        return "\(sky.drawCount) draws, turned \(Int(motion.yawDegrees.rounded()))°, \(view)"
    }

    func hideSky() {
        let shown = sky.isShown
        let trees = sky.trees
        sky = PerkSkyState()
        sky.trees = trees
        guard shown, let renderer = world?.renderer else { return }
        renderer.setMenuScene(nil)
        try? renderer.setLoadingCover(nil)
    }

    func tickSky(now: Double) {
        guard
            skyEnabled, let model, let world, let renderer = world.renderer,
            let models = world.perkSkySource?.models(device: renderer.device)
        else { return }
        if !sky.isShown {
            sky.isShown = true
            sky.openedAt = now
            sky.anchors = model.skills.indices.map { slot in
                models.dome.nodePosition(PerkSkyLayout.anchorName(slot: slot), playing: [])
                    ?? PerkSkyLayout.defaultAnchor(slot: slot)
            }
            try? renderer.setLoadingCover([])
        }
        let settings = world.perkSkySettings
        let elapsed = now - (sky.openedAt ?? now)
        var motion = sky.motion ?? PerkSkyMotion(slot: model.skillPosition)
        let intro = models.dome.sequence("CameraIntro")
        let introSeconds = Double(intro?.duration ?? 0)
        let clock = introSeconds > 0 ? Float(elapsed / introSeconds) : 1
        motion.introAlpha = min(1, max(0, sky.movieAlpha ?? clock))
        motion.update(
            now: now, slot: model.skillPosition, slotCount: model.skills.count,
            inTree: model.page == .perks, settings: settings
        )
        sky.motion = motion
        let introOffset = intro.flatMap { sequence in
            models.dome.nodePosition("CameraPosition", playing: [
                .init(sequence, seconds: motion.introAlpha * sequence.duration)
            ])
        } ?? .zero
        let camera = PerkSkyLayout.camera(
            yawDegrees: motion.yawDegrees, treeBlend: motion.treeBlend,
            introOffset: introOffset, settings: settings
        )
        var scene = MenuScene(
            eye: camera.eye, target: camera.target, up: camera.up,
            fovYRadians: settings.cameraFOV * .pi / 180
        )
        scene.draws = domeDraws(models, elapsed: elapsed, introSeconds: introSeconds, camera)
        let frame = PerkSkyFrame(
            models: models, settings: settings, now: now, camera: camera,
            beamLength: models.line.nodePosition("BeamEnd", playing: []).map(simd_length) ?? 0
        )
        let trees = treeDraws(model, frame)
        scene.draws += trees.lines + trees.stars
        sky.lastTick = now
        sky.drawCount = scene.draws.count
        renderer.setMenuScene(scene)
        updateNames(model, scene: scene, selectedStars: trees.openTree, renderer: renderer)
    }

    private func domeDraws(
        _ models: PerkSkySource.Models, elapsed: Double, introSeconds: Double,
        _ camera: PerkSkyCamera
    ) -> [MenuSceneDraw] {
        let playing: NIFEffectPose.Playing? = if elapsed < introSeconds {
            models.dome.sequence("CameraIntro").map { .init($0, seconds: Float(elapsed)) }
        } else {
            models.dome.sequence("Idle").map { .init($0, seconds: Float(elapsed - introSeconds)) }
        }
        return models.dome.draws(
            playing: playing.map { [$0] } ?? [], placement: matrix_identity_float4x4,
            eye: camera.eye, up: camera.up
        )
    }

    private func treeDraws(_ model: SkillsMenuModel, _ frame: PerkSkyFrame) -> PerkSkyTreeDraws {
        var draws = PerkSkyTreeDraws()
        var starKeys = Set<PerkStarKey>()
        var lineKeys = Set<PerkLineKey>()
        for (slot, skill) in model.skills.enumerated() where sky.anchors.indices.contains(slot) {
            let isOpenTree = slot == model.skillPosition && model.page == .perks
            let perks = isOpenTree ? model.perks : sky.trees[skill.index] ?? []
            let stars = PerkSkyLayout.stars(
                perks, slot: slot, anchor: sky.anchors[slot],
                selected: isOpenTree ? model.selectedPerk?.node : nil, settings: frame.settings
            )
            if isOpenTree {
                draws.openTree = stars
            }
            for star in stars {
                let key = PerkStarKey(skill: skill.index, node: star.node)
                starKeys.insert(key)
                draws.stars += starDraw(star, key: key, frame)
            }
            for line in PerkSkyLayout.lines(perks, stars: stars) {
                let key = PerkLineKey(skill: skill.index, parent: line.parent, child: line.child)
                lineKeys.insert(key)
                draws.lines += lineDraw(line, key: key, frame)
            }
        }
        sky.stars.keep(starKeys)
        sky.lines.keep(lineKeys)
        return draws
    }

    private func starDraw(
        _ star: PerkSkyStar, key: PerkStarKey, _ frame: PerkSkyFrame
    ) -> [MenuSceneDraw] {
        let mesh = frame.models.star
        let now = frame.now
        let playback = sky.stars.playback(
            key, state: star.state.rawValue,
            transition: { PerkStarState(rawValue: $0)?.transition(to: star.state) },
            now: now, duration: { mesh.sequence($0)?.duration }
        )
        guard let sequence = mesh.sequence(playback.sequence) else { return [] }
        playSounds(sequence, playback: playback, now: now)
        let placement = Self.translation(star.position) * Self.scale(frame.settings.starScale)
        return mesh.draws(
            playing: [.init(sequence, seconds: playback.seconds(at: now))],
            placement: placement, eye: frame.camera.eye, up: frame.camera.up
        )
    }

    private func lineDraw(
        _ line: PerkSkyLine, key: PerkLineKey, _ frame: PerkSkyFrame
    ) -> [MenuSceneDraw] {
        let mesh = frame.models.line
        let now = frame.now
        let length = frame.beamLength
        let playback = sky.lines.playback(
            key, state: line.state.rawValue,
            transition: { PerkLineState(rawValue: $0)?.transition(to: line.state) },
            now: now, duration: { mesh.sequence($0)?.duration }
        )
        guard let sequence = mesh.sequence(playback.sequence), length > 0 else { return [] }
        let placement = Self.lineBasis(
            from: line.from, to: line.to, meshLength: length, width: frame.settings.lineScale
        )
        return mesh.draws(
            playing: [.init(sequence, seconds: playback.seconds(at: now))],
            placement: placement, eye: frame.camera.eye, up: frame.camera.up
        )
    }

    /// Plays the `SoundPlay.` text keys a transition passed since the last frame.
    private func playSounds(_ sequence: NIFSequence, playback: PerkSkyPlayback, now: Double) {
        guard playback.next != nil, let player = world?.renderer?.swfSoundPlayer else { return }
        let last = sky.lastTick ?? now
        for key in sequence.textKeys where key.value.hasPrefix(Self.soundKeyPrefix) {
            let time = playback.started + Double(key.time)
            guard time > last, time <= now else { continue }
            player(String(key.value.dropFirst(Self.soundKeyPrefix.count)))
        }
    }

    /// Sends the selected tree's names where their stars land, when they moved.
    private func updateNames(
        _ model: SkillsMenuModel, scene: MenuScene, selectedStars: [PerkSkyStar],
        renderer: Renderer
    ) {
        var points: [UInt32: SIMD2<Float>] = [:]
        for star in selectedStars {
            points[star.node] = scene.screenPoint(
                star.position, aspectRatio: renderer.drawableAspectRatio
            )
        }
        let moved = points.count != sky.namePoints.count || points.contains { node, point in
            sky.namePoints[node].map { simd_distance($0, point) > Self.nameTolerance } ?? true
        }
        guard moved else { return }
        sky.namePoints = points
        guard movieLoaded, model.page == .perks else { return }
        try? renderer.updateSWFRuntime { runtime in
            StatsMenuMovieBridge.publishPerkNames(model, points: points, runtime: runtime)
        }
    }

    static func translation(_ position: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(position, 1)
        return matrix
    }

    static func scale(_ factor: Float) -> float4x4 {
        float4x4(diagonal: SIMD4(factor, factor, factor, 1))
    }

    /// The line mesh runs along +Y to `BeamEnd`; this stretches it from `from` to `to`.
    static func lineBasis(
        from: SIMD3<Float>, to: SIMD3<Float>, meshLength: Float, width: Float
    ) -> float4x4 {
        let along = to - from
        let distance = simd_length(along)
        guard distance > .ulpOfOne else { return translation(from) * scale(0) }
        let axis = along / distance
        let helper: SIMD3<Float> = abs(axis.z) < 0.9 ? [0, 0, 1] : [1, 0, 0]
        let side = simd_normalize(simd_cross(axis, helper))
        let normal = simd_cross(side, axis)
        return float4x4(columns: (
            SIMD4(side * width, 0), SIMD4(axis * (distance / meshLength), 0),
            SIMD4(normal * width, 0), SIMD4(from, 1)
        ))
    }
}
