// The session port and frame driver calls, each answered by the part that owns it.

import OpenSkyCamera
import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

extension GameSession {
    public func updateWeather(deltaTime: Float) {
        weatherSteps.updateWeather(deltaTime: deltaTime)
    }

    public func clearScriptScreenEffects() {
        weatherSteps.clearScriptScreenEffects()
    }

    public func reseedMovement(camera newCamera: SceneCamera) {
        movementSteps.reseedMovement(camera: newCamera)
    }

    public func placePlayerFeet(at feet: SIMD3<Float>) {
        movementSteps.placePlayerFeet(at: feet)
    }

    public func seatPlayer(at root: float4x4, head: SIMD3<Float>?) {
        movementSteps.seatPlayer(at: root, head: head)
    }

    public func setMovementMode(_ mode: CameraMovementMode) {
        movementSteps.setMovementMode(mode)
    }

    public func settlePlayerOnGround() -> Bool {
        movementSteps.settlePlayerOnGround()
    }

    public func setDialogueCameraFocus(_ focus: DialogueCameraFocus?) {
        dialogueCameraSteps.setDialogueCameraFocus(focus)
    }

    public var playerEyePosition: SIMD3<Float> {
        dialogueCameraSteps.playerEyePosition
    }

    public var isCinematicCameraEngaged: Bool {
        cinematicSteps.isCinematicCameraEngaged
    }

    public func setCinematicCamera(
        _ pose: CinematicCameraPose?,
        shakeOffset: SIMD3<Float> = .zero
    ) {
        cinematicSteps.setCinematicCamera(pose, shakeOffset: shakeOffset)
    }

    public var sessionFOVYRadians: Float {
        rigSteps.sessionFOVYRadians
    }

    public func setFirstPersonFOVY(radians: Float) {
        rigSteps.setFirstPersonFOVY(radians: radians)
    }

    public var gameClock: GameClock {
        get { clockSteps.gameClock }
        set { clockSteps.gameClock = newValue }
    }

    public var currentTimescale: Float {
        clockSteps.currentTimescale
    }

    public var lastAudioUpdateMS: Double {
        audio.lastAudioUpdateMS
    }

    var weatherEnabled: Bool {
        get { sky.weatherEnabled }
        set { sky.weatherEnabled = newValue }
    }
}
