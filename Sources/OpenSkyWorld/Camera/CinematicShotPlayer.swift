// Plays a chosen CAMS sequence: one stage per shot, each held between its min
// and max time, the eye placed by the shot's camera mesh relative to its anchor
// actor. Rules and their sources: docs/engine/kill-cam.md#playing-a-shot.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

/// Where one actor or projectile stands, for placing a cinematic eye.
nonisolated public struct CinematicAnchor: Equatable, Sendable {
    public var position: SIMD3<Float>
    /// Heading in radians around +Z; the camera mesh is authored in this frame.
    public var yaw: Float
    /// Height of the point the camera looks at, such as the chest.
    public var focusHeight: Float

    public init(position: SIMD3<Float>, yaw: Float, focusHeight: Float = 96) {
        self.position = position
        self.yaw = yaw
        self.focusHeight = focusHeight
    }

    public var focus: SIMD3<Float> {
        position + SIMD3(0, 0, focusHeight)
    }
}

nonisolated public struct CinematicAnchors: Equatable, Sendable {
    public var attacker: CinematicAnchor
    public var target: CinematicAnchor?
    public var projectile: CinematicAnchor?

    public init(
        attacker: CinematicAnchor,
        target: CinematicAnchor?,
        projectile: CinematicAnchor? = nil
    ) {
        self.attacker = attacker
        self.target = target
        self.projectile = projectile
    }

    /// CAMS location and target values: 0 attacker, 1 projectile, 2 target, 3 lead actor.
    public func anchor(_ value: UInt32) -> CinematicAnchor {
        switch value {
        case 1: projectile ?? target ?? attacker
        case 2: target ?? attacker
        default: attacker
        }
    }
}

nonisolated public struct CinematicCameraPose: Equatable, Sendable {
    public var eye: SIMD3<Float>
    public var lookAt: SIMD3<Float>
    /// False for a map view, which looks down through terrain and roofs on
    /// purpose. A shot near the ground pulls its eye in front of geometry.
    public var avoidsGeometry: Bool

    public init(eye: SIMD3<Float>, lookAt: SIMD3<Float>, avoidsGeometry: Bool = true) {
        self.eye = eye
        self.lookAt = lookAt
        self.avoidsGeometry = avoidsGeometry
    }
}

nonisolated public struct CinematicStage: Sendable {
    public let shot: ResolvedRecord<CameraShot>
    public let track: NIFCameraTrack?
    public let duration: Double
    public let minimum: Double

    public init(shot: ResolvedRecord<CameraShot>, track: NIFCameraTrack?) {
        self.shot = shot
        self.track = track
        let properties = shot.record.properties
        let minimum = Double(max(0, properties?.minTime ?? 0))
        let maximum = Double(max(0, properties?.maxTime ?? 0))
        let natural = track.map { Double(max(0, $0.stopTime - $0.startTime)) } ?? 0
        var duration = natural > 0 ? natural : CinematicShotPlayer.fallbackStageSeconds
        // `ExitPlaybackCamHolder`, the shot of every `Exit` path, sets both times to 0.
        if let properties, properties.minTime == 0, properties.maxTime == 0 {
            duration = 0
        }
        if maximum > 0 {
            duration = min(duration, maximum)
        }
        self.minimum = minimum
        self.duration = max(duration, minimum)
    }

    /// CAMS flag 0x02: the camera turns to keep the target in view.
    public var rotationFollowsTarget: Bool {
        (shot.record.properties?.flags ?? 0) & 0x02 != 0
    }

    public var timeScale: Float {
        CinematicTimeScale.worldScale(shot.record.properties?.timeMultipliers)
    }
}

/// The world clock under a shot: the global multiplier times the slower of
/// the player and target multipliers. OpenSky runs one world clock.
nonisolated public enum CinematicTimeScale {
    public static let minimum: Float = 0.01

    public static func worldScale(_ multipliers: SIMD3<Float>?) -> Float {
        guard let multipliers else { return 1 }
        let actors = min(multipliers.x, multipliers.y)
        let scale = multipliers.z * (actors > 0 ? actors : 1)
        guard scale.isFinite, scale > 0 else { return 1 }
        return min(max(scale, minimum), 1)
    }
}

nonisolated public struct CinematicShotPlayer: Sendable {
    /// A stage whose mesh has no keys and whose CAMS caps no time.
    public static let fallbackStageSeconds = 1.5

    public let stages: [CinematicStage]
    public private(set) var stageIndex = 0
    /// Real seconds into the current stage; the camera runs at real time.
    public private(set) var stageTime: Double = 0
    public private(set) var isFinished: Bool

    public init(stages: [CinematicStage]) {
        self.stages = stages
        isFinished = stages.isEmpty
    }

    public var currentStage: CinematicStage? {
        isFinished ? nil : stages[stageIndex]
    }

    public var remainingSeconds: Double {
        guard let stage = currentStage else { return 0 }
        return max(0, stage.duration - stageTime)
            + stages.dropFirst(stageIndex + 1).reduce(0) { $0 + $1.duration }
    }

    /// The world clock scale while the current stage plays.
    public var worldTimeScale: Float {
        currentStage?.timeScale ?? 1
    }

    /// A long frame carries its leftover time into the next stages.
    public mutating func advance(realSeconds: Double) {
        stageTime += max(0, realSeconds)
        while let stage = currentStage, stageTime >= stage.duration {
            let leftover = stageTime - stage.duration
            nextStage()
            stageTime = leftover
        }
    }

    /// The stage's event happened, such as the arrow hitting during the fly
    /// stage. The stage ends once its minimum time has passed.
    public mutating func endStageEarly() {
        guard let stage = currentStage, stageTime >= stage.minimum else { return }
        nextStage()
    }

    public mutating func stop() {
        isFinished = true
    }

    public func pose(anchors: CinematicAnchors) -> CinematicCameraPose? {
        guard let stage = currentStage else { return nil }
        let properties = stage.shot.record.properties
        let origin = anchors.anchor(properties?.location ?? 0)
        let target = anchors.anchor(properties?.target ?? 2)
        let localTime = Float(stageTime) + (stage.track?.startTime ?? 0)
        let turn = simd_quatf(angle: origin.yaw, axis: [0, 0, 1])
        let offset = stage.track?.translation(at: localTime) ?? Self.fallbackOffset
        let eye = origin.position + turn.act(offset)
        guard !stage.rotationFollowsTarget, let track = stage.track else {
            return CinematicCameraPose(eye: eye, lookAt: target.focus)
        }
        // A Gamebryo camera looks down its local +X axis.
        let forward = (turn * track.rotation(at: localTime)).act([1, 0, 0])
        return CinematicCameraPose(eye: eye, lookAt: eye + forward * 100)
    }

    private static let fallbackOffset = SIMD3<Float>(-60, -160, 110)

    private mutating func nextStage() {
        stageTime = 0
        if stageIndex + 1 < stages.count {
            stageIndex += 1
        } else {
            isFinished = true
        }
    }
}
