// Part of the `GameSession` state, held in one object so the session port can name it.

import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWeather
public import OpenSkyWorldInterface
import simd

/// The player body, the first-person arms, and the camera states that frame them.
public final class SessionRigs {
    /// Orbit framing and collision zoom for `.thirdPerson`. Pure math; holds no pose.
    public var thirdPersonCamera = ThirdPersonCamera()
    /// The conversation camera's focus, framing and saved player pose. An override on top
    /// of `movementMode`, never a mode (GameSession+DialogueCamera.swift).
    public var dialogueCameraState = RendererDialogueCameraState()
    /// The kill-cam pose and camera shake, applied over the dialogue camera.
    public var cinematicCameraState = RendererCinematicCameraState()
    /// The player's rendered body, attached once the app has assembled it and
    /// deliberately not part of the scene: it survives every cell swap
    /// (GameSession+PlayerBody.swift). nil in offscreen/CLI paths and until the
    /// assembly succeeds. Set through `setPlayerBody`, which also sizes the
    /// rings and manages residency; assigning it directly would draw from
    /// buffers the GPU has not been told about.
    public var playerBody: PlayerBody?
    /// The player's first-person arms, held like `playerBody`. Set through
    /// `setPlayerFirstPersonRig`.
    public var playerFirstPersonRig: PlayerFirstPersonRig?
    /// First-person field of view and the arms' depth policy. Holds no pose.
    public var firstPersonCamera = FirstPersonCamera()
    /// Toggle for the arms, so a capture can tell an arm fault from a world fault.
    public var firstPersonArmsEnabled = true

    public init() {}
}
