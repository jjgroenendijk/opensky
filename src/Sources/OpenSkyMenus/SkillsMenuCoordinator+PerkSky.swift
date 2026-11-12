// The perk sky behind the skills menu: the dome, every tree's stars and lines, and
// the camera, rebuilt each frame as a menu scene. The world stays hidden under an
// empty loading cover. See docs/engine/perk-sky.md.

import Foundation
import OpenSkyFormatsCore
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

/// The dome's sequence names, as `intperkskydome.nif` has them.
enum PerkSkyDome {
    static let introSequence = "CameraIntro"
    static let idleSequence = "Idle"
    static let outroSequence = "CameraOutro"
    static let cameraNode = "CameraPosition"
}

/// One frame of the dome: the sequence it plays and how far it lifts the camera.
struct PerkSkyDomePose {
    let playing: NIFEffectPose.Playing?
    let lift: SIMD3<Float>
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
    /// When `CameraOutro` started, after a close.
    var closedAt: Double?
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
        let view = if isClosing {
            "closing"
        } else {
            motion.treeBlend >= 1 ? "tree view" : motion.treeBlend > 0 ? "moving" : "ring"
        }
        return "\(sky.drawCount) draws, turned \(Int(motion.yawDegrees.rounded()))°, \(view)"
    }

    func hideSky() {
        let shown = sky.isShown
        let trees = sky.trees
        sky = PerkSkyState()
        sky.trees = trees
        guard shown, let renderer = world?.renderer else { return }
        renderer.setMenuScene(nil)
        attempt { try renderer.setLoadingCover(nil) }
    }

    func tickSky(now: Double) {
        guard
            skyEnabled, let model, let world, let renderer = world.renderer,
            let models = world.perkSkySource?.models(device: renderer.device)
        else {
            if isClosing {
                finishClose()
            }
            return
        }
        let drawn = sky.draw(
            model, models: models, clock: (now, isClosing),
            output: (world.perkSkySettings, renderer)
        )
        guard let drawn else {
            finishClose()
            return
        }
        renderer.setMenuScene(drawn.scene)
        updateNames(model, scene: drawn.scene, selectedStars: drawn.openTree, renderer: renderer)
    }

    /// Sends the selected tree's names where their stars land, when they moved.
    private func updateNames(
        _ model: SkillsMenuModel, scene: MenuScene, selectedStars: [PerkSkyStar],
        renderer: any RendererPort
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
        guard movieLoaded, model.isInTree else { return }
        attempt {
            try renderer.updateSWFRuntime { runtime in
                StatsMenuMovieBridge.publishPerkNames(model, points: points, runtime: runtime)
            }
        }
    }
}

extension PerkSkyState {
    /// Steps the sky to `clock.now` and returns its scene and the open tree's stars.
    /// Nil once the closing move has ended.
    mutating func draw(
        _ model: SkillsMenuModel, models: PerkSkySource.Models,
        clock: (now: Double, isClosing: Bool),
        output: (settings: PerkSkySettings, renderer: any RendererPort)
    ) -> (scene: MenuScene, openTree: [PerkSkyStar])? {
        let (now, isClosing) = clock
        let (settings, renderer) = output
        if !isShown {
            isShown = true
            openedAt = now
            anchors = model.skills.indices.map { slot in
                models.dome.nodePosition(PerkSkyLayout.anchorName(slot: slot), playing: [])
                    ?? PerkSkyLayout.defaultAnchor(slot: slot)
            }
            attempt { try renderer.setLoadingCover([]) }
        }
        if isClosing, closedAt == nil {
            closedAt = now
        }
        let elapsed = now - (openedAt ?? now)
        var moving = motion ?? PerkSkyMotion(slot: model.skillPosition)
        let intro = models.dome.sequence(PerkSkyDome.introSequence)
        let introSeconds = Double(intro?.duration ?? 0)
        let introClock = introSeconds > 0 ? Float(elapsed / introSeconds) : 1
        moving.introAlpha = min(1, max(0, movieAlpha ?? introClock))
        moving.update(
            now: now, ring: (model.skillPosition, model.skills.count),
            inTree: model.isInTree, settings: settings
        )
        motion = moving
        guard let pose = domePose(models.dome, elapsed: elapsed, now: now, motion: moving) else {
            return nil
        }
        let camera = PerkSkyLayout.camera(
            yawDegrees: moving.yawDegrees, treeBlend: moving.treeBlend,
            introOffset: pose.lift, settings: settings
        )
        var scene = MenuScene(
            eye: camera.eye, target: camera.target, up: camera.up,
            fovYRadians: settings.cameraFOV * .pi / 180
        )
        scene.draws = models.dome.draws(
            playing: pose.playing.map { [$0] } ?? [], placement: matrix_identity_float4x4,
            eye: camera.eye, up: camera.up
        )
        let frame = PerkSkyFrame(
            models: models, settings: settings, now: now, camera: camera,
            beamLength: models.line.nodePosition("BeamEnd", playing: []).map(simd_length) ?? 0
        )
        let trees = treeDraws(model, frame, soundPlayer: renderer.swfSoundPlayer)
        scene.draws += trees.lines + trees.stars
        lastTick = now
        drawCount = scene.draws.count
        return (scene, trees.openTree)
    }

    /// The dome sequence at this moment and the camera lift from its `CameraPosition`:
    /// `CameraIntro` on open, then `Idle`, and `CameraOutro` after a close. Nil once
    /// the closing move has ended.
    func domePose(
        _ dome: MenuSceneModel, elapsed: Double, now: Double, motion: PerkSkyMotion
    ) -> PerkSkyDomePose? {
        if let closedAt {
            guard let outro = dome.sequence(PerkSkyDome.outroSequence) else { return nil }
            let seconds = Float(now - closedAt)
            guard seconds < outro.duration else { return nil }
            let playing = NIFEffectPose.Playing(outro, seconds: seconds)
            return PerkSkyDomePose(playing: playing, lift: Self.lift(dome, playing))
        }
        let intro = dome.sequence(PerkSkyDome.introSequence)
        let lift = intro
            .map { Self.lift(dome, .init($0, seconds: motion.introAlpha * $0.duration)) }
        let introSeconds = Double(intro?.duration ?? 0)
        let playing: NIFEffectPose.Playing? = if elapsed < introSeconds {
            intro.map { .init($0, seconds: Float(elapsed)) }
        } else {
            dome.sequence(PerkSkyDome.idleSequence)
                .map { .init($0, seconds: Float(elapsed - introSeconds)) }
        }
        return PerkSkyDomePose(playing: playing, lift: lift ?? .zero)
    }

    private static func lift(
        _ dome: MenuSceneModel,
        _ playing: NIFEffectPose.Playing
    ) -> SIMD3<Float> {
        dome.nodePosition(PerkSkyDome.cameraNode, playing: [playing]) ?? .zero
    }

    mutating func treeDraws(
        _ model: SkillsMenuModel, _ frame: PerkSkyFrame, soundPlayer: ((String) -> Void)?
    ) -> PerkSkyTreeDraws {
        var draws = PerkSkyTreeDraws()
        var starKeys = Set<PerkStarKey>()
        var lineKeys = Set<PerkLineKey>()
        for (slot, skill) in model.skills.enumerated() where anchors.indices.contains(slot) {
            let isOpenTree = slot == model.skillPosition && model.isInTree
            let perks = isOpenTree ? model.perks : trees[skill.index] ?? []
            let stars = PerkSkyLayout.stars(
                perks, at: (slot, anchors[slot]),
                selected: isOpenTree ? model.selectedPerk?.node : nil, settings: frame.settings
            )
            if isOpenTree {
                draws.openTree = stars
            }
            for star in stars {
                let key = PerkStarKey(skill: skill.index, node: star.node)
                starKeys.insert(key)
                draws.stars += starDraw(star, key: key, frame, soundPlayer: soundPlayer)
            }
            for line in PerkSkyLayout.lines(perks, stars: stars) {
                let key = PerkLineKey(skill: skill.index, parent: line.parent, child: line.child)
                lineKeys.insert(key)
                draws.lines += lineDraw(line, key: key, frame)
            }
        }
        stars.keep(starKeys)
        lines.keep(lineKeys)
        return draws
    }

    private mutating func starDraw(
        _ star: PerkSkyStar, key: PerkStarKey, _ frame: PerkSkyFrame,
        soundPlayer: ((String) -> Void)?
    ) -> [MenuSceneDraw] {
        let mesh = frame.models.star
        let now = frame.now
        let playback = stars.playback(
            key, state: star.state.rawValue,
            transition: { PerkStarState(rawValue: $0)?.transition(to: star.state) },
            at: (now, { mesh.sequence($0)?.duration })
        )
        guard let sequence = mesh.sequence(playback.sequence) else { return [] }
        playSounds(sequence, playback: playback, at: (now, soundPlayer))
        let placement = Self.translation(star.position) * Self.scale(frame.settings.starScale)
        return mesh.draws(
            playing: [.init(sequence, seconds: playback.seconds(at: now))],
            placement: placement, eye: frame.camera.eye, up: frame.camera.up
        )
    }

    private mutating func lineDraw(
        _ line: PerkSkyLine, key: PerkLineKey, _ frame: PerkSkyFrame
    ) -> [MenuSceneDraw] {
        let mesh = frame.models.line
        let now = frame.now
        let length = frame.beamLength
        let playback = lines.playback(
            key, state: line.state.rawValue,
            transition: { PerkLineState(rawValue: $0)?.transition(to: line.state) },
            at: (now, { mesh.sequence($0)?.duration })
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
    private func playSounds(
        _ sequence: NIFSequence, playback: PerkSkyPlayback,
        at moment: (now: Double, player: ((String) -> Void)?)
    ) {
        let now = moment.now
        guard playback.next != nil, let player = moment.player else { return }
        let last = lastTick ?? now
        for key in sequence.textKeys
            where key.value.hasPrefix(SkillsMenuCoordinator.soundKeyPrefix)
        {
            let time = playback.started + Double(key.time)
            guard time > last, time <= now else { continue }
            player(String(key.value.dropFirst(SkillsMenuCoordinator.soundKeyPrefix.count)))
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
