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
