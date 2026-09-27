// Where the eye sits while a conversation is open (issue #427, roadmap item
// 17.4).
//
// ## Not a fourth camera mode
//
// `CameraMovementMode` is what the player chose to look through; a conversation
// is something that happens to them. So the dialogue camera is an override the
// renderer applies on top of whichever mode is live and takes back off when the
// menu closes, never a case in the G-key cycle. Nothing about the player's own
// mode, capsule or facing changes while it is engaged.
//
// ## Where the numbers come from
//
// Nothing in the readable install frames a conversation. The probe is on
// record: `openskycli gmst list --prefix f` over the user's own `Skyrim.esm`
// declares no `fDialogueCamera*`, no `fOverShoulder*` and no camera framing
// setting of any kind — the only dialogue-adjacent distances it carries are
// `fAIInDialogueModeWithPlayerDistance` (500) and
// `fAIInDialogueModewithPlayerTimer` (60), which decide when an actor considers
// itself in conversation rather than where a camera stands, and the
// `fAIHeadTrackDialogue*` family, which is head tracking and out of scope here.
// The retail executable holds the rest and OpenSky does not read it.
//
// So the framing is derived from the two things that *are* measurable: the
// player capsule (`PlayerCapsule.standard`, derived in
// docs/engine/walk-mode.md) and the vertical field of view the scene pass
// projects with. The one taste number — how much of the frame the subject
// fills — is not re-decided here; it is `ThirdPersonCamera.framingFillFraction`,
// so the engine makes that call exactly once.
//
// ## The shot
//
// The camera looks at the speaker's head from the side of it the player is
// standing on, offset to the shoulder so the shot is three-quarter rather than
// flat head-on, and stands either at the framing distance or just behind the
// player — whichever is further from the speaker. That second clause is what
// keeps the player's own body in the frame instead of behind the lens: a player
// who walked right up gets the tight framing distance, and a player who started
// the conversation from across the room gets a camera at their shoulder rather
// than one hovering between them and the speaker.
//
// See docs/engine/dialogue.md, "Dialogue camera".

import simd

/// What one frame of the dialogue camera is computed from. Everything here is
/// world space and sampled by the caller, so the framing math needs no streamer,
/// no renderer and no game data to be tested.
nonisolated struct DialogueCameraSubject: Equatable, Sendable {
    /// The speaker's head, world space: the `NPC Head [Head]` bone of its own
    /// posed rig where one is sampled, its capsule eye height otherwise.
    let headPosition: SIMD3<Float>
    /// Where the player's eye is — the capsule's eye height above its feet,
    /// which is where `.walk` puts the first-person eye, and *not* wherever the
    /// third-person orbit happens to have put the camera this frame.
    let playerEyePosition: SIMD3<Float>
    /// The capsule the framing distance is derived from. A parameter rather
    /// than a constant so the derivation can be tested against a capsule other
    /// than the standard one, which is the only capsule this engine resolves.
    var capsule: PlayerCapsule = .standard
}

/// One resolved frame: where to look from, what to look at, and what the
/// collision sweep did about it.
nonisolated struct DialogueCameraPose: Equatable, Sendable {
    let eye: SIMD3<Float>
    /// The point the camera is aimed at, which is the speaker's head.
    let target: SIMD3<Float>
    let yaw: Float
    let pitch: Float
    /// Eye-to-target distance after the collision pull-in.
    let distance: Float
    /// True when world geometry, rather than the framing rule, decided that
    /// distance.
    let isCollisionLimited: Bool
}

nonisolated struct DialogueCamera: Equatable {
    /// The vertical field of view a conversation is projected with: the shared
    /// world value, so engaging the camera in first person also takes the
    /// first-person comfort setting off the world for the duration and gives
    /// every conversation the same framing. Asserted against the renderer by
    /// `DialogueCameraTests`.
    static let fovYRadians = FirstPersonCamera.defaultFOVYRadians

    /// How much of the frame's height the framed span occupies. Deliberately
    /// the third-person camera's fraction rather than a second taste decision:
    /// the two cameras frame different spans, and that is the only thing that
    /// should differ between them.
    static let framingFillFraction = ThirdPersonCamera.framingFillFraction

    /// The rig bone the camera aims at. Present in the third-person skeleton
    /// (`meshes/actors/character/character assets/skeleton.hkx`, bone list read
    /// with `openskycli skeleton`), which is the rig every resident actor is
    /// animated on.
    static let headBoneName = "NPC Head [Head]"

    /// The vertical span the shot frames: the head at its centre, reaching down
    /// to the capsule's own midpoint and as far above the head as that is
    /// below it. Head and chest for the standard capsule, 96 units, which is
    /// what makes this a conversation shot rather than the full-body shot
    /// `ThirdPersonCamera` frames.
    static func framedHeight(capsule: PlayerCapsule = .standard) -> Float {
        max(capsule.radius, 2 * (capsule.eyeHeight - capsule.height / 2))
    }

    /// Distance from the speaker's head at which `framedHeight` fills
    /// `framingFillFraction` of the view height:
    /// `(height / 2 / fill) / tan(fov / 2)`. About 126 units for the standard
    /// capsule and a 65-degree vertical field of view.
    static func framingDistance(capsule: PlayerCapsule = .standard) -> Float {
        (framedHeight(capsule: capsule) / 2 / framingFillFraction) / tanf(fovYRadians / 2)
    }

    /// How far right of the sightline the eye sits, which is what makes the
    /// shot three-quarter rather than flat head-on. One capsule radius, and the
    /// same side `ThirdPersonCamera` offsets to, so the player's body stays on
    /// the side of the frame it was already on when the conversation started.
    static let shoulderOffset = ThirdPersonCamera.shoulderOffset

    /// How far behind the player's own eye the camera stands when the player is
    /// further from the speaker than the framing distance. The third-person
    /// camera's own minimum, which is one capsule radius: enough to put the
    /// lens outside the player's silhouette and no more.
    static let clearanceBehindPlayer = ThirdPersonCamera.minimumDistance

    /// The pull-in. A conversation happens indoors as often as not, so the
    /// camera has to be able to end up tight against a wall; it collides with
    /// the same probe and through the same seam third person does, and may
    /// never be pushed closer to the speaker than one capsule radius, which is
    /// the point at which it would be inside their head.
    static let collisionProbe = CameraCollisionProbe(
        radius: ThirdPersonCamera.collisionRadius,
        minimumDistance: PlayerCapsule.standard.radius
    )

    /// The last resolved frame, or nil before the first one. Kept so the panel
    /// can report where the camera is and what it is looking at, and so the
    /// debug overlay can draw the pivot without resolving a second time.
    private(set) var pose: DialogueCameraPose?

    /// Resolves this frame's pose from the speaker's head and the player's eye.
    ///
    /// The ideal eye is placed in the horizontal plane through the *player's*
    /// eye rather than through the speaker's head, so a conversation with
    /// somebody taller looks up at them instead of levelling the shot out.
    mutating func resolve(
        subject: DialogueCameraSubject,
        collisionQuery: WalkController.CollisionQuery
    ) -> DialogueCameraPose {
        let target = subject.headPosition
        let toPlayer = subject.playerEyePosition - target
        let level = SIMD3<Float>(toPlayer.x, toPlayer.y, 0)
        let span = simd_length(level)
        // A player standing exactly inside the speaker names no side to watch
        // from. World +X is as good as any other and is at least the same
        // answer every frame, which a flickering fallback would not be.
        let direction = span > .ulpOfOne ? level / span : SIMD3<Float>(1, 0, 0)
        // `direction` points from the speaker back towards the player, which is
        // the camera's *backward*. The camera's right is therefore the right of
        // the negated direction: in this basis, `right` for a view along
        // `forward` is `(sin yaw, -cos yaw)`, so it comes out as below rather
        // than as the perpendicular of `direction` itself.
        let right = SIMD3<Float>(-direction.y, direction.x, 0)
        let standOff = max(
            Self.framingDistance(capsule: subject.capsule),
            span + Self.clearanceBehindPlayer
        )
        let base = SIMD3<Float>(target.x, target.y, subject.playerEyePosition.z)
        let ideal = base + direction * standOff + right * Self.shoulderOffset
        let resolved = Self.collisionProbe.resolve(
            pivot: target,
            offset: ideal - target,
            collisionQuery: collisionQuery
        )
        let look = target - resolved.position
        let horizontal = simd_length(SIMD2<Float>(look.x, look.y))
        let resolvedPose = DialogueCameraPose(
            eye: resolved.position,
            target: target,
            yaw: horizontal > .ulpOfOne ? atan2f(look.y, look.x) : 0,
            pitch: FreeFlyCamera.clampPitch(atan2f(look.z, horizontal)),
            distance: resolved.distance,
            isCollisionLimited: resolved.isCollisionLimited
        )
        pose = resolvedPose
        return resolvedPose
    }

    /// Forgets the last frame, so a conversation does not open reporting where
    /// the previous one's camera stood.
    mutating func reset() {
        pose = nil
    }
}
